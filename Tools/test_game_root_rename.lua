-- 遊戲根目錄改名之後，讀卡器還是要開得動卡，而且不能變慢。
--
--   Tools\lua\lua.exe Tools\test_game_root_rename.lua [--card PATH] [--rounds 2] [--limit 20] [--mcp EXE] [--keep]
--
-- 為什麼要有這個測試（使用者 2026-11-24：「我這是萬人遊戲，你怎麼能假設大家路徑一樣」「每台電腦都不一樣」）：
-- 原作遊戲在每個人的電腦上都放在不同地方，也隨時會被搬走或改名。程式裡不能有任何寫死的路徑，而且「路徑和上次
-- 不一樣」這件事本身不能讓開卡變慢——它會讓所有以 mods 資料夾路徑當 key 的東西全部失效並重建：讀卡器的 GUID
-- 索引（Saved/mod_index.json）與 ok-extract 自己的 zipmod 盤點（遊戲目錄下的 .ok_cache.sqlite）。這台機器上那是
-- 7,296 個 zipmod；重建一次要是走錯路（整包讀、在遊戲執行緒上做），就是使用者 2026-11-24 遇到的「拖一張卡進去
-- 整個凍住」。
--
-- 它做什麼：把遊戲根目錄改名成 <原名>.okrename<N>，用新路徑底下的同一張卡，在一個全新的讀卡器裡開一次，計時；
-- 下一輪換一個名字再來一次。每一輪都是「這個路徑第一次見到」，所以量到的就是索引與盤點重建的代價。開卡時間
-- 超過 --limit（預設 20 秒）就算失敗。
--
-- 它不做什麼：不量正常（路徑沒變）的開卡——那是 Tools\card_open_baseline.lua 的事。
--
-- 安全：
--   * 跑之前會確認沒有別的 Unreal 在跑。別人的 session 正在用同一個遊戲資料夾時改名會害到他們，也會因為檔案被
--     占用而改不動。
--   * 不管成功失敗、按 Ctrl+C 或中途出錯，最後一定把名字改回去；萬一真的沒改回去，畫面上會印出改回去的指令。
--   * 卡片路徑與遊戲路徑都從參數或使用者自己的設定來，腳本裡沒有任何寫死的路徑。
local ok = require "ok"
local path = require "ok.path"
local proc = require "ok.proc"
local json = require "ok.json"
local clock = require("ok.time").clock  -- 牆上時間（os.clock 是 CPU 時間，開卡大半在等 I/O 與別的執行緒）

local root = path.parent(path.parent(path.abs(arg[0])))

local USAGE = [[
Tools\lua\lua.exe Tools\test_game_root_rename.lua [--card PATH] [--rounds 2] [--limit 20] [--mcp EXE] [--keep]
  --card    原作遊戲資料夾裡的一張人物卡（例如 <遊戲>\UserData\chara\female\xxx.png）。
            沒給就用讀卡器設定的遊戲目錄（GameUserSettings.ini 的 [OKGameRoot] Root）底下第一張女性卡。
  --rounds  改名幾次（預設 2：改一次讀一次，再改一次再讀一次）
  --limit   每一輪開卡的秒數上限（預設 20）
  --keep    失敗時不要把名字改回去（留著現場給人看）
]]

local o = { rounds = 2, limit = 20 }
do
  local i = 1
  while arg[i] do
    local k = arg[i]
    if k == "--keep" then o.keep = true; i = i + 1
    elseif k == "--help" or k == "-h" then io.write(USAGE); os.exit(0)
    elseif k:sub(1, 2) == "--" then
      local name = k:sub(3)
      local value = arg[i + 1]
      if not value then error(("%s 要帶一個值\n%s"):format(k, USAGE)) end
      o[name] = tonumber(value) or value
      i = i + 2
    else error(("看不懂的參數 %q\n%s"):format(k, USAGE)) end
  end
end

local function say(fmt, ...) io.write(select("#", ...) > 0 and fmt:format(...) or fmt, "\n"); io.flush() end
local function sleep(seconds) os.execute(("ping -n %d 127.0.0.1 >nul"):format(math.max(1, math.floor(seconds + .5)) + 1)) end

-- 使用者自己設的遊戲目錄（讀卡器「設定 › 遊戲目錄」寫在這裡），沒有就是空的。
local function configured_root()
  for _, file in ipairs({ "Saved/Config/WindowsEditor/GameUserSettings.ini", "Saved/Config/Windows/GameUserSettings.ini" }) do
    local full = path.join(root, file)
    if path.is_file(full) then
      local section
      for line in (path.read_text(full) or ""):gmatch("[^\r\n]+") do
        local header = line:match("^%[(.-)%]$")
        if header then section = header
        elseif section == "OKGameRoot" then
          local value = line:match("^Root=(.*)$")
          if value and value ~= "" then return value end
        end
      end
    end
  end
  return nil
end

-- 卡片往上找到遊戲安裝：和讀卡器用的規則一樣（abdata/ 與 UserData/ 都在，而且有原作的執行檔）。
local function game_root_of(card)
  local dir = path.parent(path.abs(card))
  while dir and dir ~= "" do
    if path.is_dir(path.join(dir, "abdata")) and path.is_dir(path.join(dir, "UserData"))
      and (path.is_file(path.join(dir, "KoikatsuSunshine.exe")) or path.is_file(path.join(dir, "Koikatu.exe"))) then
      return dir
    end
    local parent = path.parent(dir)
    if parent == dir then return nil end
    dir = parent
  end
  return nil
end

local function first_card(game)
  local folder = path.join(game, "UserData/chara/female")
  if not path.is_dir(folder) then return nil end
  local names = path.list(folder)
  table.sort(names)
  for _, name in ipairs(names) do
    if name:lower():match("%.png$") then return path.join(folder, name) end
  end
  return nil
end

local card = o.card
if not card then
  local configured = configured_root()
  if not configured then
    error("找不到卡片：讀卡器還沒設遊戲目錄，請用 --card 指定遊戲資料夾裡的一張卡\n" .. USAGE)
  end
  card = first_card(configured)
  if not card then error(("設定的遊戲目錄 %s 底下沒有女性卡，請用 --card 指定\n%s"):format(configured, USAGE)) end
end
card = path.abs(card)
if not path.is_file(card) then error("卡片不存在：" .. card) end

local game = game_root_of(card)
if not game then error(("%s 不在原作遊戲資料夾裡（往上找不到同時有 abdata\\、UserData\\ 與原作執行檔的資料夾），這個測試要的是遊戲自己的卡"):format(card)) end
local relative = path.abs(card):sub(#path.abs(game) + 2)
say("遊戲 %s", game)
say("卡片 %s（遊戲底下的 %s）", card, relative)

-- 別人的 Unreal 正在跑就不要動這個資料夾。
do
  local running = proc.output({ "powershell", "-NoProfile", "-NonInteractive", "-Command",
    "@(Get-Process -Name UnrealEditor,OpenKoikatsu -ErrorAction SilentlyContinue).Count" }, { check = false }) or ""
  local count = tonumber(running:match("%d+") or "0") or 0
  if count > 0 then
    error(("現在有 %d 個 Unreal 在跑。改遊戲資料夾的名字會害到正在用它的人，也可能因為檔案被占用而改不動；先把它們關掉再跑。"):format(count))
  end
end

local mcp = o.mcp or path.join(root, "Tools/ok-game-mcp/target/release/ok-game-mcp.exe")
if not path.is_file(mcp) then error("找不到 ok-game-mcp：" .. mcp) end

local function mcp_call(tool, payload)
  local out = proc.output({ mcp, "call", tool, json.encode(payload or {}) }, { check = false }) or ""
  return out
end

-- 這一輪用的新名字，以及它是怎麼來的："rename"（真的改名）或 "junction"（接點）。
local made_to, made_how = nil, nil
local function restore()
  if not made_to then return end
  if made_how == "junction" then
    -- 只拆接點，不碰它指到的真資料夾（AGENTS.md：有 junction 的目錄不要遞迴刪）。
    proc.output({ "cmd", "/c", "rmdir", (made_to:gsub("/", "\\")) }, { check = false })
    if path.is_dir(made_to) then say("！拆不掉接點：請自己執行  rmdir \"%s\"", made_to) else made_to = nil end
  elseif path.is_dir(made_to) then
    local okay = pcall(path.rename, made_to, game)
    if okay then made_to = nil
    else say("！改不回來：請自己執行  ren \"%s\" \"%s\"", made_to, path.basename(game)) end
  end
end

local results = {}
local function round(n)
  local target = ("%s.okrename%d"):format(game, n)
  if path.is_dir(target) then error("要用的名字已經存在：" .. target) end
  -- 先真的改名。改不動是常有的事（玩家的檔案總管開在那個資料夾裡、遊戲正開著、防毒在掃），那就退而求其次：
  -- 用一個新名字的接點指向同一個資料夾。對程式來說一樣是「這個遊戲路徑第一次見到」——索引與 zipmod 盤點照樣
  -- 整個重建，量到的代價相同——但不會動到別人正在用的資料夾。
  local renamed = pcall(path.rename, game, target)
  if renamed then
    made_to, made_how = target, "rename"
  else
    -- 每個參數分開傳：整句塞進一個參數時，CreateProcess 的引號會被 cmd 再吃一層，mklink 就看不懂了。
    local out = proc.output({ "cmd", "/c", "mklink", "/J", (target:gsub("/", "\\")), (game:gsub("/", "\\")) }, { check = false }) or ""
    if not path.is_dir(target) then
      error(("改名被拒，接點也建不起來：%s　（那個資料夾被占用。把開在它裡面的檔案總管關掉、確認原作遊戲沒在跑，再試一次）"):format(out:gsub("%s+$", "")))
    end
    made_to, made_how = target, "junction"
  end
  say("")
  say("第 %d 輪：遊戲變成 %s（%s）", n, target, made_how == "rename" and "改名" or "接點，因為那個資料夾被占用、改不動名字")

  local moved_card = path.join(target, relative)
  if not path.is_file(moved_card) then error("改名之後找不到卡片：" .. moved_card) end

  local launched = mcp_call("reader_launch", { lane = ("rename%d"):format(n), no_build = true, timeout_s = 450 })
  local pid = tonumber(launched:match('"pid"%s*:%s*(%d+)'))
  if not pid then error("讀卡器沒起來：" .. launched) end
  say("讀卡器 pid=%d", pid)

  local began = clock()
  local answer = mcp_call("reader_call", { action = "load", path = moved_card, timeout_s = o.limit + 60 })
  local took = clock() - began
  -- 開好了的樣子：reader_call 回的狀態裡 card 換成了這張（改名後的路徑），而且 status 是 applied。
  local wanted = moved_card:gsub("\\", "/")
  local loaded = answer:find('"status"%s*:%s*"applied"') ~= nil and answer:find(wanted:gsub("%p", "%%%0")) ~= nil
  mcp_call("reader_stop", { pid = pid })
  sleep(3)
  restore()

  results[#results + 1] = { round = n, seconds = took, loaded = loaded, answer = answer }
  say("第 %d 輪：%s，%.1f 秒（上限 %d）", n, loaded and "開起來了" or "沒開起來", took, o.limit)
  if not loaded then say("   回答：%s", (answer:gsub("%s+", " "):sub(1, 400))) end
end

local run_ok, err = pcall(function()
  for n = 1, math.max(1, math.floor(o.rounds)) do round(n) end
end)
if not (run_ok and o.keep) then restore() end
if not run_ok then
  restore()
  say("RESULT fail %s", tostring(err))
  os.exit(2)
end

local worst, failed = 0, 0
for _, r in ipairs(results) do
  worst = math.max(worst, r.seconds)
  if not r.loaded or r.seconds > o.limit then failed = failed + 1 end
end
say("")
say("RESULT %s rounds=%d worst=%.1fs limit=%ds", failed == 0 and "pass" or "fail", #results, worst, o.limit)
os.exit(failed == 0 and 0 or 1)
