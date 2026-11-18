-- 遊戲卡住了嗎？（Tools\lua\lua.exe Tools\ok_hang_check.lua）
--
-- GPU 卡死（DXGI_ERROR_DEVICE_HUNG）之後，遊戲視窗還在、控制通道還在聽，但永遠不會再回應。自動化那條路由
-- ok-game-mcp 的 watchdog 自己處理（逾時就強制結束，Docs/GAME_CONTROL_CHANNELS.md）；**自己開的視窗不會被自動關掉**，
-- 因為那是使用者的視窗，殺掉他連畫面都來不及看。這支就是給那種時候用的：一眼看出哪個行程沒回應、log 與 GPU crash
-- dump 在哪、以及要自己關的話該下哪一行。它只看不動，不會結束任何行程。
--
--   Tools\lua\lua.exe Tools\ok_hang_check.lua                 現在的狀況（每個登記中的遊戲一行）
--   Tools\lua\lua.exe Tools\ok_hang_check.lua --watch --pid=N  一直盯著，它沒回應的那一刻印一行
--   Tools\lua\lua.exe Tools\ok_hang_check.lua --watch-newest    同上，盯剛啟動的那個（手開的 .cmd 用這個）
--
-- 卡住會回結束碼 2。
local ok = require "ok"
local json, path, proc = ok.json, ok.path, ok.proc

local root = ok.root

-- Saved/OKControl/<pid>.json：每個跑著的遊戲自己寫的通道登記（埠、模式、信箱）。
local function instances()
  local dir = path.join(root, "Saved", "OKControl")
  local out = {}
  if not path.is_dir(dir) then return out end
  for _, name in ipairs(path.list(dir)) do
    local pid = name:match("^(%d+)%.json$")
    if pid then
      local okv, v = pcall(function() return json.decode(path.read_text(path.join(dir, name))) end)
      if okv and type(v) == "table" then
        v.pid = tonumber(pid)
        out[#out + 1] = v
      end
    end
  end
  table.sort(out, function(a, b) return (a.pid or 0) < (b.pid or 0) end)
  return out
end

local function alive(pid)
  local out = proc.output({ "powershell", "-NoProfile", "-NonInteractive", "-Command",
    ("[bool](Get-Process -Id %d -ErrorAction SilentlyContinue)"):format(pid) }, { check = false }) or ""
  return out:lower():find("true") ~= nil
end

-- 問它的 UI 通道 /health；秒數短，卡死的遊戲不會回。
local function answers(port, seconds)
  if not port then return false end
  local script = ("try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec %d -Uri 'http://127.0.0.1:%s/health'; if ($r.StatusCode -eq 200) { 'yes' } } catch { }")
    :format(seconds or 3, tostring(port))
  local out = proc.output({ "powershell", "-NoProfile", "-NonInteractive", "-Command", script }, { check = false }) or ""
  return out:find("yes") ~= nil
end

-- 這個行程最後寫的 log，與最新的 crash dump 目錄（證據，別刪）。
local function newest(dir, pattern)
  if not path.is_dir(dir) then return nil end
  local best, best_time
  for _, name in ipairs(path.list(dir)) do
    if not pattern or name:find(pattern) then
      local full = path.join(dir, name)
      local t = path.mtime(full)
      if t and (not best_time or t > best_time) then best, best_time = full, t end
    end
  end
  return best
end

-- 這個行程的 log：啟動器自己的收據（`Saved/Logs/<模式>/<tag>.json`，裡面有 pid 與 log）才知道是哪一個檔。
-- 找不到收據才退回「目錄裡最新的那個」，並在印的時候講明那是猜的（別的 session 的讀卡器也在寫 log）。
local function log_of(pid)
  for _, dir in ipairs({ path.join(root, "Saved", "Logs", "CardReader"), path.join(root, "Saved", "Logs") }) do
    if path.is_dir(dir) then
      for _, name in ipairs(path.list(dir)) do
        if name:match("%.json$") then
          local okv, v = pcall(function() return json.decode(path.read_text(path.join(dir, name))) end)
          if okv and type(v) == "table" and tonumber(v.pid) == pid and v.log then return v.log, false end
        end
      end
    end
  end
  return newest(path.join(root, "Saved", "Logs", "CardReader")) or newest(path.join(root, "Saved", "Logs")), true
end

local function mode_of(v) return v.game_mode or v.mode or v.map or "?" end

local function look(v)
  local running = alive(v.pid)
  local answering = running and answers(v.port_ui, 3)
  return running, answering
end

-- 卡住的那幾行（以及該怎麼辦）。印完就回：這支程式永遠不結束任何行程。
local function report_stuck(v)
  io.write(("pid %d（%s）：**沒有回應**（UI 通道 127.0.0.1:%s 三秒內不回）。GPU 卡死就是這個樣子。\n")
    :format(v.pid, mode_of(v), tostring(v.port_ui)))
  local log, guessed = log_of(v.pid)
  if log then
    io.write(("  log%s：%s\n"):format(guessed and "（最新的那個，不一定是它的）" or "", log))
  end
  io.write(("  GPU crash dump 與當機紀錄：%s\n"):format(path.join(root, "Saved", "Crashes")))
  io.write("  要自己關掉它（這支程式不會替你關）：\n")
  io.write(("    Tools\\ok-game-mcp\\target\\release\\ok-game-mcp.exe call reader_stop '{\"pid\": %d}'\n"):format(v.pid))
  io.write("  log 與 dump 請留著，那是查卡死原因的唯一證據。\n")
  io.flush()
end

-- 等一下，不要忙等（powershell 的 Start-Sleep，和其他探测共用同一个壳）。
local function nap(seconds)
  proc.output({ "powershell", "-NoProfile", "-NonInteractive", "-Command",
    ("Start-Sleep -Seconds %d"):format(seconds) }, { check = false })
end

local function instance_of(pid)
  for _, v in ipairs(instances()) do if v.pid == pid then return v end end
end

-- --watch：手開的視窗留著這一行盯著遊戲。沒回應的那一刻就印出來然後結束（非零），不碰那個行程。
--
-- 两段：先等它第一次回應（啟動要幾十秒，這段不算卡住），之后才判斷。判斷要**连续** FAILS_TO_CALL 次
-- 失败才算卡住（一次探测失败可能只是它正忙着開一张大卡），这就是「探 /health 失败且持续一段时间」。
local FAILS_TO_CALL = 3
-- 它從來沒回應過一次就不再等（啟動本來就要幾十秒，但永遠不回代表它在啟動時就死了／卡了）。
local STARTUP_GRACE = 240
local function watch(pid, every, grace)
  grace = grace or STARTUP_GRACE
  io.write(("盯著 pid %d（每 %d 秒探一次 /health；連續 %d 次不回才算卡住）。它卡住或結束時這裡會印一行；"):format(pid, every, FAILS_TO_CALL))
  io.write("這個視窗可以隨時關掉，不影響遊戲。\n")
  io.flush()
  local answered_once, fails, waited_for_first = false, 0, 0
  while true do
    local found = instance_of(pid)
    if not found then
      io.write(("pid %d 的登記檔不見了，不再盯。\n"):format(pid))
      return 0
    end
    local running, answering = look(found)
    if not running then
      io.write(("pid %d（%s）已經結束了。\n"):format(pid, mode_of(found)))
      return 0
    end
    if answering then
      answered_once, fails = true, 0
    elseif not answered_once then
      waited_for_first = waited_for_first + every
      if waited_for_first >= grace then
        io.write(("pid %d（%s）啟動了 %d 秒，控制通道一次都沒有回應（127.0.0.1:%s）。\n")
          :format(pid, mode_of(found), waited_for_first, tostring(found.port_ui)))
        report_stuck(found)
        return 2
      end
    else
      fails = fails + 1
      if fails >= FAILS_TO_CALL then
        io.write(("連續 %d 次（約 %d 秒）沒有回應。\n"):format(fails, fails * every))
        report_stuck(found)
        return 2
      end
    end
    nap(every)
  end
end

-- --watch-newest：手開的 .cmd 用的。啟動器一回來就跑這個，等最新登記的那個遊戲出現（它可能還在啟動），
-- 然后盯着它。等不到就说一声走人，绝不乱盯别的 session 的游戏。
local function newest_instance(since)
  local best
  for _, v in ipairs(instances()) do
    local t = path.mtime(path.join(root, "Saved", "OKControl", tostring(v.pid) .. ".json"))
    if t and t >= since and alive(v.pid) and (not best or t > best.at) then best = { v = v, at = t } end
  end
  return best and best.v
end

local function watch_newest(since, every, wait_for, grace)
  local waited = 0
  while waited < wait_for do
    local v = newest_instance(since)
    if v then return watch(v.pid, every, grace) end
    nap(5)
    waited = waited + 5
  end
  io.write(("等了 %d 秒都沒有新的遊戲登記（Saved/OKControl），不盯了。\n"):format(wait_for))
  return 0
end

local function main()
  local do_watch, newest, watch_pid, every, grace = false, false, nil, 10, nil
  for i = 1, #arg do
    local a = arg[i]
    if a == "--watch" then do_watch = true
    elseif a == "--watch-newest" then do_watch, newest = true, true
    elseif a:match("^%-%-pid=%d+$") then watch_pid = tonumber(a:match("(%d+)"))
    elseif a:match("^%-%-every=%d+$") then every = tonumber(a:match("(%d+)"))
    elseif a:match("^%-%-grace=%d+$") then grace = tonumber(a:match("(%d+)"))
    elseif a:match("^%d+$") then watch_pid = tonumber(a)
    end
  end

  if do_watch then
    if newest and not watch_pid then
      -- 登記檔可能比這個行程早几秒写出来（啟動器先 spawn、游戏再登記），所以往前留一点。
      os.exit(watch_newest(os.time() - 120, every, 300, grace))
    end
    if not watch_pid then
      local only = instances()
      if #only ~= 1 then
        io.write("--watch 要指名 pid（--pid=N），或用 --watch-newest：現在登記著的遊戲不只一個。\n")
        os.exit(1)
      end
      watch_pid = only[1].pid
    end
    os.exit(watch(watch_pid, every, grace))
  end

  local list = instances()
  if #list == 0 then
    io.write("沒有登記中的遊戲（Saved/OKControl 沒有紀錄）。視窗還在的話，它可能是舊版啟動的，用工作管理員看。\n")
    return
  end
  local stuck = 0
  for _, v in ipairs(list) do
    local running, answering = look(v)
    if not running then
      io.write(("pid %d（%s）：行程已經不在，登記檔是舊的。\n"):format(v.pid, mode_of(v)))
    elseif answering then
      io.write(("pid %d（%s）：正常，控制通道有回應。\n"):format(v.pid, mode_of(v)))
    else
      stuck = stuck + 1
      report_stuck(v)
    end
  end
  if stuck > 0 then os.exit(2) end
end

ok.main(main)
