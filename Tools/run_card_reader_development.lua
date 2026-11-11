-- Card reader (OpenKoikatsuGameMode) in UnrealEditor -game (CardReaderDevelopment.cmd).
--
--   Tools\lua\lua.exe Tools\run_card_reader_development.lua [-CardDirectory DIR | -StreetHeroines] [-WindowWidth N]
--     [-WindowHeight N] [-CpuSkin] [-Engine ROOT] [-NoBuild] [-DryRun] [-- UNREAL_ARGS...]
-- Option names are case-insensitive and may also be written --card-directory, ... ; -Name:value works too.
--
-- Before launching, the editor build must match the shared engine (Tools/ok_editor_modules.lua). When another checkout
-- rebuilt the engine, this checkout's OpenKoikatsuEditor is rebuilt here (-NoEngineChanges) unless -NoBuild is given.
-- Cards: Content/CharacterCards/CrowdAPNG by default; -StreetHeroines opens Content/CharacterCards/StreetHeroines (the
-- street mode's heroines, also the reader's "街頭女主角卡片" source); -CardDirectory "" uses the saved/game-backed selection.
local ok = require "ok"
local json, path, proc = ok.json, ok.path, ok.proc
local fs = require "okfs"
local editor = require "ok_editor_modules"
local instance = require "ok_instance"
local player_settings = require "street_player_settings"

local SWITCHES = { cpuskin = true, nobuild = true, dryrun = true, streetheroines = true }
local VALUES = { carddirectory = true, windowwidth = true, windowheight = true, engine = true }

local function parse(argv)
  local o, i = {}, 1
  o.passthrough = {}
  while i <= #argv do
    local raw = argv[i]
    -- Everything after "--" goes to UnrealEditor unchanged (-CharacterMCP, -CharacterMCPCard=..., ...).
    if raw == "--" then table.move(argv, i + 1, #argv, 1, o.passthrough); break end
    local name, inline = raw:match("^%-%-?([%w%-]+):(.*)$")
    if not name then name = raw:match("^%-%-?([%w%-]+)$") end
    if not name then error("unexpected argument: " .. raw, 0) end
    local key = name:gsub("%-", ""):lower()
    if SWITCHES[key] then o[key] = true
    elseif VALUES[key] then
      local v = inline
      if v == nil then i = i + 1; v = argv[i] end
      if v == nil then error("missing value for " .. raw, 0) end
      o[key] = v
    else error("unknown option: " .. raw, 0) end
    i = i + 1
  end
  return o
end

local function size(o, key, default, lo, hi)
  local v = o[key] and tonumber(o[key]) or default
  if not v or v ~= math.floor(v) or v < lo or v > hi then error(("%s must be an integer %d..%d"):format(key, lo, hi), 0) end
  return v
end

local function main()
  local o = parse(arg)
  local root = ok.root
  local engine = o.engine and path.abs(o.engine) or ok.engine_root()
  local width = size(o, "windowwidth", 1600, 640, 7680)
  local height = size(o, "windowheight", 1000, 480, 4320)
  local gpu = not o.cpuskin

  -- The prepared APNG library by default; an explicit directory (even "") wins.
  local street = path.join(root, "Content/CharacterCards/StreetHeroines")
  if o.streetheroines and o.carddirectory ~= nil then error("-StreetHeroines and -CardDirectory are exclusive", 0) end
  local cards = o.streetheroines and street or o.carddirectory
  if cards == nil then
    local prepared = path.join(root, "Content/CharacterCards/CrowdAPNG")
    cards = path.is_dir(prepared) and prepared or ""
  end
  if cards ~= "" then
    cards = path.abs(cards)
    if not path.is_dir(cards) then error("Card directory does not exist: " .. cards, 0) end
  end

  editor.ensure(root, engine, { build = not o.nobuild and not o.dryrun })

  local project = path.join(root, "OpenKoikatsu.uproject")
  local exe = path.join(engine, "Engine/Binaries/Win64/UnrealEditor.exe")
  local manifest = path.join(root, "Binaries/Win64/UnrealEditor.modules")
  for _, f in ipairs({ project, exe, manifest }) do
    if not path.is_file(f) then error("Missing launch dependency: " .. f, 0) end
  end
  local module = json.decode((path.read_text(manifest):gsub("^\239\187\191", ""))).Modules.OpenKoikatsu
  module = module and path.join(path.parent(manifest), module)
  if not module or not path.is_file(module) then error("Missing project module: " .. tostring(module), 0) end

  local log_root = path.join(root, "Saved/Logs/CardReader")
  local tag = os.date("%Y%m%d-%H%M%S") .. ("-%08x"):format(math.random(0, 0x7fffffff))
  local log = path.join(log_root, tag .. ".log")
  -- Explicit map and game mode: a saved crowd/demo startup map must not take over.
  local args = { exe, project, "/Engine/Maps/Templates/Template_Default?game=/Script/OpenKoikatsu.OpenKoikatsuGameMode", "-game", "-windowed",
    "-ResX=" .. width, "-ResY=" .. height, "-NoSplash", "-nop4", "-abslog=" .. log, table.unpack(o.passthrough) }
  local receipt = json.object({ { "project", project }, { "executable", exe }, { "arguments", json.array({ table.unpack(args, 2) }) },
    { "module", module }, { "card_directory", cards }, { "log", log }, { "skinning", gpu and "GPU" or "CPU" } })
  if o.dryrun then io.write(json.encode(receipt, { indent = 2, ensure_ascii = false }), "\n"); return end

  path.mkdir(log_root, true)
  -- Video motion demos ship in Content (Saved/ is disposable); the reader lists Saved/VideoMotions, so missing ones
  -- are copied there (a motion of the same name the user made is kept).
  local demos, motions = path.join(root, "Content/IndependentResources/VideoMotionDemos"), path.join(root, "Saved/VideoMotions")
  if path.is_dir(demos) then
    path.mkdir(motions, true)
    for _, f in ipairs(path.iterdir(demos)) do
      local dst = path.join(motions, path.name(f))
      if path.is_file(f) and not path.exists(dst) then path.write_bytes(dst, path.read_bytes(f)) end
    end
  end
  -- The one-on-one talks like the street's (Source/OpenKoikatsu/OKReaderTalk.h): the heroine mind (a copy of its DLL, so
  -- cargo can rebuild it meanwhile), the street's main settings (DeepSeek key, voice), its personas, and ok-tts for her
  -- spoken lines. This checkout's ok-tts port; a server already on it (the street's) is used, else one starts with the
  -- reader and exits with it. Without the DLL or a key she just does not answer.
  local ports = instance.ports(root)
  local settings_file = path.join(root, "Saved/StreetSocial/player.json")
  local tts_endpoint = ports.voice and ("http://127.0.0.1:" .. ports.tts) or (fs.getenv("OK_TTS_ENDPOINT") or ("http://127.0.0.1:" .. ports.tts))
  local mind_source = path.join(root, "Tools/ok-mind/target/release/ok_mind.dll")
  local mind_dll = path.join(root, "Saved/CardReader/ok-mind/ok_mind.dll")
  if path.is_file(mind_source) then
    path.mkdir(path.parent(mind_dll), true)
    local copied = pcall(path.copy, mind_source, mind_dll)
    if not copied then io.write("Heroine mind DLL in use, keeping the previous copy\n") end
  end
  local tts = path.join(root, "Build/ok-tts/ok-tts.exe")
  local voice_mode = path.is_file(settings_file) and player_settings.read(settings_file).voice.voice_mode or nil
  local start_tts = ports.voice and voice_mode ~= "off" and path.is_file(tts)
  -- Explicit mode overrides inherited diagnostics; CPU skinning stays available for side-by-side checks.
  local env = {
    OK_FREE_TALK_SETTINGS = path.is_file(settings_file) and (settings_file:gsub("/", "\\")) or false,
    OK_FREE_TALK_PERSONAS = (path.join(root, "Content/IndependentResources/StreetSocialData/free_talk_personas.json"):gsub("/", "\\")),
    OK_TTS_ENDPOINT = tts_endpoint,
    OK_MIND_DLL = path.is_file(mind_dll) and (mind_dll:gsub("/", "\\")) or false, OK_AUTO_3D = "0", OK_AUTO_CARD = false, OK_CARD_DIRECTORY = cards ~= "" and (cards:gsub("/", "\\")) or false,
    OK_WARM_PRIORITY = false,
    OK_CPU_SKIN = gpu and "0" or "1", OK_GPU_SKIN = gpu and "1" or "0", OK_SKELMESH = gpu and "1" or "0",
    OK_NOPOSE = false, OK_UE_ANIM = false, OK_HEAD_GPUSKIN = false }
  local saved = {}
  for k, v in pairs(env) do saved[k] = fs.getenv(k) or false; fs.setenv(k, v or nil) end
  local okv, pid = pcall(proc.spawn, args, { cwd = root })
  for k, v in pairs(saved) do fs.setenv(k, v or nil) end
  if not okv then error(pid, 0) end
  receipt.pid = pid
  -- A second server on a port already taken just exits: the one there keeps serving.
  if start_tts and not o.dryrun then
    local args = { tts, "serve", "--port", tostring(ports.tts), "--settings", settings_file, "--parent-pid", tostring(pid) }
    local size = player_settings.read(settings_file).voice.tts_base_size
    if size == "1.7B" or size == "0.6B" then table.insert(args, 6, "--base-size"); table.insert(args, 7, size) end
    pcall(proc.spawn, args, { cwd = path.parent(tts), hide = true })
    io.write("TTS server for her lines on port ", tostring(ports.tts), " (exits with the reader)\n")
  end
  -- No background warm-up of the open-card cache (ok-card-warm): the reader builds each card when it opens it.
  path.write_text(path.join(log_root, tag .. ".json"), json.encode(receipt, { indent = 2, ensure_ascii = false }))
  io.write("Card reader started. PID=", tostring(pid), "\nLog: ", log, "\n")
end

ok.main(main)
