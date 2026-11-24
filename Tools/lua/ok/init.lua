-- ok: shared library for OpenKoikatsu Lua scripts.
--   local ok = require "ok"
-- Loading it makes io.open/io.lines/io.popen/os.remove/os.rename/os.execute/
-- os.getenv UTF-8 aware (Windows wide APIs), re-reads `arg` as UTF-8, switches
-- the console to UTF-8 and puts the calling script's folder on package.path so
-- sibling modules load with require.
local fs = require "okfs"

if not rawget(_G, "__ok_patched") then
  rawset(_G, "__ok_patched", true)
  io.open, io.popen = fs.open, fs.popen
  local raw_lines = io.lines
  io.lines = function(path, ...)
    if path == nil then return raw_lines() end
    local f = assert(fs.open(path, "r"))
    local it = f:lines(...)
    return function()
      local a, b, c = it()
      if a == nil then f:close() end
      return a, b, c
    end, nil, nil, f
  end
  os.remove, os.execute, os.getenv = fs.remove, fs.execute, fs.getenv
  os.rename = function(a, b) return fs.rename(a, b, false) end
  fs.utf8_console()
  -- lua.exe receives argv in the ANSI code page; rebuild arg from the wide command line.
  if arg then
    rawset(_G, "__ok_arg0_raw", arg[0])
    local raw, n, count = fs.args(), 0, #arg
    for i in pairs(raw) do if i > n then n = i end end
    for k = 0, count do
      local v = raw[n - count + k]
      if v then arg[k] = v end
    end
  end
end

local function script_dir()
  local s = arg and arg[0]
  if not s then return "." end
  s = s:gsub("\\", "/")
  return s:match("^(.*)/[^/]*$") or "."
end

local ok = {}
ok.fs = fs
ok.script_dir = fs.fullpath(script_dir()):gsub("\\", "/")
package.path = ok.script_dir .. "/?.lua;" .. package.path

-- Repository root: this file lives at <root>/Tools/lua/ok/init.lua.
do
  local src = debug.getinfo(1, "S").source:gsub("^@", "")
  ok.root = (fs.fullpath(src .. "/../../../..")):gsub("\\", "/")
end
ok.lua_exe = ok.root .. "/Tools/lua/lua.exe"
-- Shared Tools/ modules are reachable from any script directory.
package.path = package.path .. ";" .. ok.root .. "/Tools/?.lua"

-- Unreal Engine root this project builds with (forward slashes, no trailing slash).
-- Tools/ok_engine.lua prints it for .cmd launchers. Order: OK_ENGINE_ROOT, Tools/engine.local.json {"engine": ...},
-- then an engine beside this checkout. No path is written in here: every machine keeps the engine somewhere else.
-- nil when none is found. Launchers shipped in a package call this: a package runs its staged game and has no engine.
function ok.find_engine_root()
  local root = os.getenv("OK_ENGINE_ROOT")
  if not root or root == "" then
    local f = io.open(ok.root .. "/Tools/engine.local.json", "rb")
    if f then local s = f:read("a"); f:close(); root = ok.json.decode((s:gsub("^\239\187\191", ""))).engine end
  end
  if not root or root == "" then
    -- An engine sitting beside this checkout, on the same drive. The last resort here used to be the literal
    -- E:/PhysX/UE5.8 -- one machine's path, and on the others a folder that is not there (here the engine is
    -- F:/UE5.8). The user, 2026-11-24:「每台電腦都不一樣」
    local drive = ok.root:match("^(%a:)") or ""
    for _, candidate in ipairs({ drive .. "/UE5.8", drive .. "/PhysX/UE5.8", ok.root .. "/../UE5.8" }) do
      local probe = io.open(candidate .. "/Engine/Binaries/Win64/UnrealEditor.exe", "rb")
      if probe then probe:close(); root = candidate; break end
    end
  end
  if not root or root == "" then return nil end
  return (root:gsub("\\", "/"):gsub("/+$", ""))
end

function ok.engine_root()
  local root = ok.find_engine_root()
  if not root then
    error("找不到 Unreal 引擎：設 OK_ENGINE_ROOT，或在 Tools/engine.local.json 寫 {\"engine\": \"<引擎資料夾>\"}")
  end
  return (root:gsub("\\", "/"):gsub("/+$", ""))
end

-- Koikatsu Sunshine installation root (forward slashes). Same rule as
-- KKLocalMods.cpp: abdata + UserData + KoikatsuSunshine.exe/Koikatu.exe.
--
-- 遊戲裝在哪每台機器都不一樣（使用者 2026-11-24：「我這是萬人遊戲，你怎麼能假設大家路徑一樣」）。這裡以前是一串
-- 寫死的位置（C:/portable/KoikatuSunshine、D:/KoikatuSunshine、E:/Koikatu…），在別人機器上全部不存在，腳本就安靜地
-- 少讀 mod。現在一律從「已經知道的東西」找起：環境變數 → 讀卡器自己設的遊戲目錄 → 專案 ini → 這個 checkout 旁邊
-- 與同磁碟根目錄下名字帶 koikat 的資料夾。
local function is_game_root(d)
  return d and fs.stat(d .. "/abdata") and fs.stat(d .. "/UserData")
    and (fs.stat(d .. "/KoikatsuSunshine.exe") or fs.stat(d .. "/Koikatu.exe")) and true or false
end
ok.is_game_root = is_game_root
-- ini 裡 [section] 底下的 key=（讀卡器的設定與專案的 DefaultGame.ini 都是這個格式）。
local function ini_value(file, section, key)
  local f = io.open(file, "rb")
  if not f then return nil end
  local text = f:read("a") or ""
  f:close()
  local current
  for line in text:gmatch("[^\r\n]+") do
    local header = line:match("^%s*%[(.-)%]%s*$")
    if header then current = header
    elseif current == section then
      local value = line:match("^%s*" .. key .. "%s*=%s*(.-)%s*$")
      if value and value ~= "" then return (value:gsub("\\", "/"):gsub("/+$", "")) end
    end
  end
  return nil
end
local function game_root_candidates()
  local out = {}
  local function add(d) if d and d ~= "" then out[#out + 1] = (d:gsub("\\", "/"):gsub("/+$", "")) end end
  add(fs.getenv("OK_GAME_ROOT"))
  -- 讀卡器「設定 › 遊戲目錄」寫的就是這個 key，使用者自己指的最準。
  for _, ini in ipairs({ "Saved/Config/WindowsEditor/GameUserSettings.ini", "Saved/Config/Windows/GameUserSettings.ini" }) do
    add(ini_value(ok.root .. "/" .. ini, "OKGameRoot", "Root"))
  end
  add(ini_value(ok.root .. "/Config/DefaultGame.ini", "/Script/KKSideloader.KKGameRoot", "Root"))
  -- 這個 checkout 旁邊、以及同磁碟根目錄下，名字帶 koikat 的資料夾（玩家自己怎麼命名都找得到）。
  local lfs_ok, lfs = pcall(require, "lfs")
  if lfs_ok then
    local parent = ok.root:match("^(.*)/[^/]+$")
    local drive = ok.root:match("^(%a:)")
    for _, where in ipairs({ parent, drive and (drive .. "/") or nil }) do
      local listed = pcall(function()
        for name in lfs.dir(where) do
          if name ~= "." and name ~= ".." and name:lower():find("koikat") then add(where:gsub("/$", "") .. "/" .. name) end
        end
      end)
      local _ = listed
    end
  end
  return out
end
local game_root_cache
-- game_root() errors when nothing is installed; game_root(true) returns "" instead
-- (for CLI defaults that are only used if needed).
-- game_root(soft, "\\") formats with backslashes.
function ok.game_root(soft, sep)
  if not game_root_cache then
    for _, candidate in ipairs(game_root_candidates()) do
      if is_game_root(candidate) then game_root_cache = candidate break end
    end
  end
  local r = game_root_cache
  if not r then
    if not soft then error("找不到 Koikatsu / Koikatsu Sunshine 安裝位置：設 OK_GAME_ROOT，或在讀卡器「設定 › 遊戲目錄」指一次", 2) end
    return ""
  end
  return sep and (r:gsub("/", sep)) or r
end
-- 舊腳本與舊資料裡寫著「當時那台機器的遊戲路徑」。那個資料夾在現在這台機器上通常不存在，就把它底下的相對位置
-- 接到真正的安裝位置上（找不到安裝位置時原樣回傳）。看的是路徑裡 abdata/、UserData/、mods/ 這些遊戲自己的資料夾。
function ok.game_path(p)
  p = tostring(p):gsub("\\", "/")
  local prefix, rest
  for _, folder in ipairs({ "[Aa]bdata", "[Uu]ser[Dd]ata", "[Mm]ods", "[Bb]ep[Ii]n[Ee]x" }) do
    prefix, rest = p:match("^(.-)/(" .. folder .. "/.*)$")
    if prefix then break end
  end
  if prefix and prefix:match("^%a:") and not is_game_root(prefix) then
    local game = ok.game_root(true)
    if game ~= "" then return game .. "/" .. rest end
  end
  return p
end

-- Python's `if __name__ == "__main__"`: call from a module's main chunk as
--   if ok.is_main() then main() end
-- True when the chunk was started by lua.exe, false when loaded via require.
-- dofile/loadfile of another script also counts as "not main".
function ok.is_main()
  local caller = debug.getinfo(3, "f")
  if caller ~= nil and caller.func == require then return false end
  local info = debug.getinfo(2, "S")
  local src = info and info.source
  if src and src:sub(1, 1) == "@" and arg and arg[0] then
    if src:sub(2) == rawget(_G, "__ok_arg0_raw") then return true end
    local a = fs.fullpath(src:sub(2)):gsub("/", "\\"):lower()
    local b = fs.fullpath(arg[0]):gsub("/", "\\"):lower()
    return a == b
  end
  return true
end

setmetatable(ok, { __index = function(t, k)
  local m = require("ok." .. k)
  rawset(t, k, m)
  return m
end })

-- Convenience re-exports used by nearly every script.
function ok.read_json(p) return ok.json.decode(ok.path.read_text(p)) end
function ok.write_json(p, v, opts) return ok.path.write_text(p, ok.json.encode(v, opts)) end
function ok.print_json(v, opts) io.write(ok.json.encode(v, opts), "\n") end
-- Python-style exit: ok.exit(true|false|code|message)
function ok.exit(v)
  io.stdout:flush()
  if type(v) == "string" then io.stderr:write(v, "\n"); os.exit(1) end
  if v == nil or v == true then os.exit(0) end
  if v == false then os.exit(1) end
  os.exit(v)
end
-- Run main inside error reporting that exits non-zero (like an uncaught Python exception).
function ok.main(fn, ...)
  local res = table.pack(xpcall(fn, debug.traceback, ...))
  if not res[1] then io.stdout:flush(); io.stderr:write(tostring(res[2]), "\n"); os.exit(1) end
  if res[2] ~= nil then ok.exit(res[2]) end
  return table.unpack(res, 2, res.n)
end

return ok
