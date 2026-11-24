-- 出貨程式裡不准寫死任何一台機器的路徑（Tools\lua\lua.exe Tools\check_absolute_paths.lua）
--
-- 使用者 2026-11-24：「我這是萬人遊戲，你怎麼能假設大家路徑一樣」「每台電腦都不一樣」「你應該用相對路徑去找」。
-- 寫死的路徑在別人機器上就是一個不存在的資料夾，而且通常不會報錯，只會安靜地少東西——讀卡器指著
-- D:/XKoikatuSunshine，卡片指名的 19 個 zipmod 只找到 1 個，衣服就變成缺貼圖的綠色（Docs/ABSOLUTE_PATHS.md）。
--
-- 看的是 Source/ 與 Plugins/ 裡會編進執行檔的程式（排除 *.spec.cpp、Tests/、Intermediate/），加上根目錄的 .cmd
-- 與 Config/*.ini。註解裡提到路徑沒關係（說明事故、舉例），所以 // 與 /* */ 與 ; 開頭的行會跳過。
-- 允許清單在下面的 ALLOW，每一條都要寫為什麼。
--
--   --list   把找到的都印出來（含允許的），不當成錯誤
local ok = require "ok"
local path, fs = ok.path, ok.fs

local ALLOW = {
  -- 第三方程式自己的安裝位置；-CrowdBlender= 可覆寫，檔案不在就直接放棄。
  { file = "Source/OpenKoikatsu/OKCrowdQuality.cpp", prefix = "C:/Program Files/Blender Foundation/" },
  -- 設定頁輸入框的提示文字，給人看的例子，程式不會去開它。
  { file = "Source/OpenKoikatsu/OKReaderScreen.cpp", prefix = "D:/KoikatuSunshine" },
  -- 規則測試的 JSON 字串（語音路徑的假值）。
  { file = "Source/OpenKoikatsu/OKStreetSocialRules.h", prefix = "C:/" },
  -- 互動 mod 測試的假語音路徑。
  { file = "Source/OpenKoikatsu/OKInteractionModTest.cpp", prefix = "C:/h/" },
  -- 作業系統自己的位置。
  { prefix = "C:/Windows" },
}

local function allowed(file, found)
  for _, rule in ipairs(ALLOW) do
    if (not rule.file or rule.file == file) and found:sub(1, #rule.prefix):lower() == rule.prefix:lower() then return true end
  end
  return false
end

-- 會編進執行檔的程式：排除測試與建置產物。
local function shipped(rel)
  if rel:find("/Intermediate/") or rel:find("/Binaries/") then return false end
  if rel:find("%.spec%.cpp$") or rel:find("/Tests/") or rel:find("Tests%.cpp$") then return false end
  return true
end

local function files()
  local out = {}
  local function walk(dir, filter)
    for _, name in ipairs(path.list(dir) or {}) do
      local full = dir .. "/" .. name
      if path.is_dir(full) then walk(full, filter)
      elseif filter(full) then out[#out + 1] = full end
    end
  end
  local function code(full) return full:find("%.cpp$") or full:find("%.h$") or full:find("%.inl$") end
  walk(ok.root .. "/Source", function(f) return code(f) and shipped(f) end)
  walk(ok.root .. "/Plugins", function(f) return code(f) and shipped(f) end)
  walk(ok.root .. "/Config", function(f) return f:find("%.ini$") end)
  for _, name in ipairs(path.list(ok.root) or {}) do
    if name:find("%.cmd$") then out[#out + 1] = ok.root .. "/" .. name end
  end
  return out
end

-- 這一行是註解嗎（整行的 //、/* …、* …、rem、;）。塊註解不追，單行判斷夠用。
local function is_comment(line)
  local t = line:gsub("^%s+", "")
  return t:sub(1, 2) == "//" or t:sub(1, 2) == "/*" or t:sub(1, 1) == "*" or t:sub(1, 1) == ";"
    or t:lower():sub(1, 4) == "rem "
end

local list = arg and arg[1] == "--list"
local bad, seen = {}, 0
for _, full in ipairs(files()) do
  local rel = full:sub(#ok.root + 2):gsub("\\", "/")
  local text = path.read_text(full)
  if text then
    local n = 0
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
      n = n + 1
      if not is_comment(line) then
        for found in line:gmatch("%f[%a]%a:[/\\][%w_%./\\%- ]*") do
          found = found:gsub("\\", "/")
          -- 單一個字母加冒號多半是別的東西（三元運算、時間），要有一段路徑才算。
          if #found > 4 then
            seen = seen + 1
            if list then print(("%s:%d  %s"):format(rel, n, found))
            elseif not allowed(rel, found) then bad[#bad + 1] = ("%s:%d  %s"):format(rel, n, found) end
          end
        end
      end
    end
  end
end

if list then print(("%d 處（含允許的）"):format(seen)) return end
if #bad == 0 then
  print(("出貨程式沒有寫死的絕對路徑（掃過 %d 處，都在允許清單裡）"):format(seen))
  return
end
print("出貨程式裡有寫死的絕對路徑：每台電腦放的位置都不一樣，這在別人機器上就是錯的。")
print("改成相對於已知的東西（程式自己的資料夾、使用者指定的資料夾、卡片自己的位置），")
print("真的是第三方或系統的位置就加進 Tools/check_absolute_paths.lua 的 ALLOW 並寫明理由。")
for _, line in ipairs(bad) do print("  " .. line) end
os.exit(1)
