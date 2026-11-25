-- 轉卡的「次序」迴歸關卡。
--
-- 2026-10-28 的 bug（Docs/ERROR_LOG.md）：同一個轉換程序裡，小绯雪 排在 Denia 後面轉時查不到
-- `[RoastDuck]Hiyuki_girl` 的 GUID，衣服、手套、鞋、頭髮配件都沒錄進卡包，而**嚴格驗收照樣通過**
-- （新卡根本不去讀那些部件，所以沒有缺口可報）。修正是每次轉換鑄一個唯一的檢視身分。
-- 任何動到那個身分的改動都要先過這一關。
--
-- 關卡怎麼判：同一批卡各自單獨轉一次當基準（一張卡一個程序，不可能受別張卡影響），再在同一程序
-- 以正序與反序各連續轉一次；每張卡轉出來的 OK 卡，**開起來的 session 位元組必須和它自己的基準逐位元組
-- 相同**。這比只比對 outfit 0 摘要強：當初那個 bug 的摘要是一樣的，差的是「錄進卡包的東西」，
-- 而少錄的部件正好會讓開卡結果不同。卡包的位元組長度本身不比對——它每次轉都會差個幾萬分之一
-- （壓縮與寫入次序），不是正確性訊號。
--
-- 用法（環境變數由呼叫者給，子程序會繼承；要量冷的就帶 OK_NOCACHE=1 OK_CARDS_IN_PROCESS=1）：
--   Tools\lua\lua.exe Tools\ok_convert_order_check.lua <遊戲> <基礎庫> <工作目錄> <卡1> <卡2> [...]
--
-- 注意：卡片路徑請用 ASCII。命令是經 cmd 下的，主控台字碼頁不是 UTF-8 時非 ASCII 檔名會被改寫成亂碼；
-- 要測非 ASCII 命名的卡，先複製成 ASCII 檔名再測（卡的內容才是受測對象，檔名不是）。

local lfs_ok, lfs = pcall(require, "lfs")

local function die(msg) io.stderr:write("ok_convert_order_check: " .. msg .. "\n"); os.exit(2) end

local game, lib, work = arg[1], arg[2], arg[3]
if not (game and lib and work and arg[4] and arg[5]) then
  die("用法：<遊戲> <基礎庫> <工作目錄> <卡1> <卡2> [...]（至少兩張卡才測得出次序問題）")
end
-- 輸出路徑拼到 cmd 裡，混用 / 和 \ 會被 cmd 當成參數開頭，一律轉成 \。
work = work:gsub("/", "\\"):gsub("\\+$", "")
local cards = {}
for i = 4, #arg do cards[#cards + 1] = arg[i] end

-- 不加引號：cmd /c 看到命令以引號開頭時會把首尾那對引號吃掉，整串參數就散了。這兩個路徑沒有空白。
local exe = "Tools\\ok-extract\\target\\release\\ok-extract.exe"
local bench = "Tools\\ok-extract\\target\\release\\ok-card-open-bench.exe"

local function mkdir(path)
  if lfs_ok then lfs.mkdir(path) else os.execute('cmd /c mkdir "' .. path .. '" 2>nul') end
end
mkdir(work)

-- 跑一個命令，stdout 與 stderr 都收進檔案再讀回來（不用 io.popen：它從 PowerShell 叫起來會是空的）。
local function run(cmd, tag)
  local log = work .. "\\" .. tag .. ".log"
  os.execute(cmd .. ' > "' .. log .. '" 2>&1')
  local f = io.open(log, "r")
  if not f then die("讀不到 " .. log .. "（命令：" .. cmd .. "）") end
  local text = f:read("*a"); f:close()
  return text, log
end

local function base_name(path) return (path:gsub("[/\\]+$", ""):gsub(".*[/\\]", "")) end

-- 一張 OK 卡的每套服裝 dump 出 session 位元組，回傳「服裝編號 -> 檔案路徑」。
local function dump_of(ok_card, tag)
  local dir = work .. "\\" .. tag
  mkdir(dir)
  run(string.format('%s --fresh-dump "%s" "%s" "%s"', bench, lib, dir, ok_card), tag .. "-dump")
  local files = {}
  if lfs_ok then
    for entry in lfs.dir(dir) do
      local outfit = entry:match("_(%d+)%.bin$")
      if outfit then files[outfit] = dir .. "\\" .. entry end
    end
  else
    die("需要 lfs 才能列出 dump 目錄")
  end
  return files
end

local function files_equal(a, b)
  local fa, fb = io.open(a, "rb"), io.open(b, "rb")
  if not (fa and fb) then if fa then fa:close() end if fb then fb:close() end return false end
  local equal = true
  while true do
    local ca, cb = fa:read(1 << 20), fb:read(1 << 20)
    if ca ~= cb then equal = false break end
    if ca == nil then break end
  end
  fa:close(); fb:close()
  return equal
end

-- dump 集合比對：服裝套數要一樣，每套的位元組要一樣。
local function dumps_equal(a, b)
  local count_a, count_b = 0, 0
  for _ in pairs(a) do count_a = count_a + 1 end
  for _ in pairs(b) do count_b = count_b + 1 end
  if count_a == 0 then return false, "基準沒有 dump 出任何服裝" end
  if count_a ~= count_b then return false, string.format("服裝套數不同（基準 %d，這次 %d）", count_a, count_b) end
  for outfit, path in pairs(a) do
    local other = b[outfit]
    if not other then return false, "少了服裝 " .. outfit end
    if not files_equal(path, other) then return false, "服裝 " .. outfit .. " 的 session 位元組不同" end
  end
  return true
end

-- 1. 基準：每張卡各自單獨轉一次。
local baseline, info = {}, {}
for i, card in ipairs(cards) do
  local tag = "solo-" .. i
  local out = work .. "\\" .. tag .. ".png"
  local text = run(string.format('%s "%s" --oklib card "%s" "%s" "%s"', exe, game, lib, card, out), tag)
  local parts, digest = text:match("OKCARD [^\n]-parts=(%d+) digest=(%S+)")
  local absent = text:match("OKCARD absent zipmods ([^\n]+)") or ""
  if not digest then
    io.write(string.format("基準 %s 轉不出來，看 %s\\%s.log\n", base_name(card), work, tag))
    die("基準就轉不出來，先把這張卡弄好再測次序")
  end
  info[card] = { digest = digest, parts = parts, absent = absent }
  baseline[card] = dump_of(out, tag .. "-d")
  local n = 0; for _ in pairs(baseline[card]) do n = n + 1 end
  io.write(string.format("基準  %-24s digest=%s parts=%s absent=[%s] dump=%d 套服裝\n",
    base_name(card), digest, parts, absent, n))
end

-- 2. 同一程序依序轉：正序與反序。
local orders = {}
do
  local forward, backward = {}, {}
  for i = 1, #cards do forward[i] = cards[i]; backward[i] = cards[#cards - i + 1] end
  orders[1] = { name = "正序", cards = forward }
  orders[2] = { name = "反序", cards = backward }
end

local failures = 0
for i, order in ipairs(orders) do
  local tag = "order-" .. i
  local list = work .. "\\" .. tag .. ".txt"
  local f = assert(io.open(list, "w"))
  for _, card in ipairs(order.cards) do f:write(card, "\n") end
  f:close()
  local out_dir = work .. "\\" .. tag
  mkdir(out_dir)
  local text = run(string.format('%s "%s" --oklib cards "%s" "%s" "%s"', exe, game, lib, list, out_dir), tag)
  io.write("\n" .. order.name .. "（同一程序依序轉）\n")
  for k, card in ipairs(order.cards) do
    local line = {}
    for l in text:gmatch("[^\n]+") do
      if l:find("OKCARDS ok", 1, true) and l:find(base_name(card), 1, true) then line = l end
    end
    local digest = type(line) == "string" and line:match("^OKCARDS ok\t.-\t(%S+)\t") or nil
    -- `absent=` is one tab-separated field of the OKCARDS line, and `missing=` follows it: `(.*)$` swallowed that
    -- one too, so an empty absent list read as `[\tmissing=]` and every in-process card "differed" from a baseline
    -- whose digest and parts were in fact identical. The gate FAILed on its own parsing (2026-11-25).
    local absent = type(line) == "string" and (line:match("absent=([^\t]*)") or "") or ""
    local ok_card = out_dir .. "\\" .. base_name(card)
    local made = io.open(ok_card, "rb")
    if made then made:close() end
    local why
    local ok = false
    if not digest or not made then
      why = "這一輪沒有轉出來（看 " .. work .. "\\" .. tag .. ".log）"
    elseif digest ~= info[card].digest then
      why = string.format("outfit 0 摘要不同（基準 %s，這次 %s）", info[card].digest, digest)
    elseif absent ~= info[card].absent then
      why = string.format("absent 清單不同（基準 [%s]，這次 [%s]）", info[card].absent, absent)
    else
      local equal, reason = dumps_equal(baseline[card], dump_of(ok_card, tag .. "-d" .. k))
      ok, why = equal, reason
    end
    if not ok then failures = failures + 1 end
    io.write(string.format("  %-4s %-24s %s\n", ok and "一致" or "不同", base_name(card), ok and "" or why))
  end
end

io.write("\n")
if failures > 0 then
  io.write(string.format("次序關卡 FAIL：%d 項和基準不同。轉卡的檢視身分讓一張卡看到了另一張卡的樹。\n", failures))
  os.exit(1)
end
io.write("次序關卡 PASS：每張卡在正序與反序下轉出來的 OK 卡，開起來都和它單獨轉的基準逐位元組相同。\n")
