-- Card reader (OpenKoikatsuGameMode) in UnrealEditor -game (CardReaderDevelopment.cmd). In a package
-- (Tools/package_street_social.lua: no project or editor) it runs in the packaged game instead: the newest stage
-- (Tools/street_stage.lua), on the cooked /Engine/Maps/Templates/Template_Default, with StreetHeroines as the default cards.
--
--   Tools\lua\lua.exe Tools\run_card_reader_development.lua [CARD.png] [-CardDirectory DIR | -StreetHeroines] [-WindowWidth N]
--     [-WindowHeight N] [-CpuSkin] [-Engine ROOT] [-NoBuild] [-DryRun] [-- UNREAL_ARGS...]
-- Option names are case-insensitive and may also be written --card-directory, ... ; -Name:value works too.
-- CARD.png (or a card dropped on CardReaderDevelopment.cmd): that card opens in 3D at once, its folder is the card wall.
-- Packaged games built before the OKCardListView fix show an empty card wall (its row class was set only in the
-- editor), so in such a package this is the way to open a card.
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
local street_stage = require "street_stage"

local SWITCHES = { cpuskin = true, nobuild = true, dryrun = true, streetheroines = true, legacyreader = true, parallelrdg = true, watch = true }
local VALUES = { carddirectory = true, windowwidth = true, windowheight = true, engine = true, physics = true }

-- -Physics <模式>（或環境變數 OK_READER_PHYSICS，選項優先：reader_launch 的 env 傳得進來）：讀卡器的
-- 頭髮／衣物／配件物理解算器，**預設是原始 Verlet**（使用者 2026-11-18）。「原始 Verlet」就是選單裡那一項：
-- OKPhysXSecondary.Enabled 0，宿主完全不接手，每條鏈都由 ok-extract 自己的 DynamicBone 更新走
-- （px.rs 的 Solver::Verlet／FLAG_BUILTIN），所以頭髮、裙擺、配件、胸臀全部一致。
-- 只影響讀卡器這條啟動路徑；街區、一對一、Studio、百人房間各自決定，不受影響。執行中仍可從選單切換。
local PHYSICS = { verlet = true, component = true, dynbone = true, physx = true, kawaii = true, chaos = true }

local function parse(argv)
  local o, i = {}, 1
  o.passthrough = {}
  while i <= #argv do
    local raw = argv[i]
    -- Everything after "--" goes to UnrealEditor unchanged (-CharacterMCP, -CharacterMCPCard=..., ...).
    if raw == "--" then table.move(argv, i + 1, #argv, 1, o.passthrough); break end
    local name, inline = raw:match("^%-%-?([%w%-]+):(.*)$")
    if not name then name = raw:match("^%-%-?([%w%-]+)$") end
    if not name then
      -- A bare argument is a card to open (a PNG dropped onto CardReaderDevelopment.cmd).
      if o.card or not raw:lower():match("%.png$") then error("unexpected argument: " .. raw, 0) end
      o.card = raw; i = i + 1; goto continue
    end
    local key = name:gsub("%-", ""):lower()
    if SWITCHES[key] then o[key] = true
    elseif VALUES[key] then
      local v = inline
      if v == nil then i = i + 1; v = argv[i] end
      if v == nil then error("missing value for " .. raw, 0) end
      o[key] = v
    else error("unknown option: " .. raw, 0) end
    i = i + 1
    ::continue::
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

  local project = path.join(root, "OpenKoikatsu.uproject")
  local editor_exe = path.join(engine, "Engine/Binaries/Win64/UnrealEditor.exe")
  local stage_exe, stage_name
  if not path.is_file(project) or not path.is_file(editor_exe) then
    local how
    stage_exe, _, stage_name, how = street_stage.newest(root, nil, "any")
    if not stage_exe then error("No editor and no usable stage in " .. street_stage.dir(root), 0) end
    io.write(("Stage: %s (newest; %s)\n"):format(stage_name, how))
  end

  -- The prepared APNG library by default (a package: its street heroines); an explicit directory (even "") wins.
  local street = path.join(root, "Content/CharacterCards/StreetHeroines")
  if o.streetheroines and o.carddirectory ~= nil then error("-StreetHeroines and -CardDirectory are exclusive", 0) end
  local card = o.card and path.abs(o.card)
  if card and not path.is_file(card) then error("Card does not exist: " .. card, 0) end
  local cards = o.streetheroines and street or o.carddirectory or (card and path.parent(card))
  -- Only a folder this launch names is forced on the reader (OK_CARD_DIRECTORY). The fallback below is just where to
  -- start when the player has never chosen one, so it goes as OK_CARD_DIRECTORY_DEFAULT and their own choice
  -- (人物卡總欄 › 選擇人物卡目錄, saved in the config) wins over it.
  local cards_chosen = cards ~= nil
  if cards == nil then
    local prepared = path.join(root, "Content/CharacterCards/CrowdAPNG")
    cards = path.is_dir(prepared) and prepared or (stage_exe and path.is_dir(street) and street) or ""
    -- A package without cards (the Studio package ships none): its own Content/CharacterCards, made empty, where the
    -- player puts theirs. "" would scan the game folder named in Config (D:/KoikatuSunshine), which a player may not
    -- have, and which held the reader at its first frame for minutes on a machine with thousands of cards there.
    if cards == "" and stage_exe then
      cards = path.join(root, "Content/CharacterCards")
      path.mkdir(cards, true)
    end
  end
  if cards ~= "" then
    cards = path.abs(cards)
    if not path.is_dir(cards) then error("Card directory does not exist: " .. cards, 0) end
  end

  local exe, module = stage_exe or editor_exe, stage_exe
  if not stage_exe then
    editor.ensure(root, engine, { build = not o.nobuild and not o.dryrun })
    local manifest = path.join(root, "Binaries/Win64/UnrealEditor.modules")
    for _, f in ipairs({ project, exe, manifest }) do
      if not path.is_file(f) then error("Missing launch dependency: " .. f, 0) end
    end
    module = json.decode((path.read_text(manifest):gsub("^\239\187\191", ""))).Modules.OpenKoikatsu
    module = module and path.join(path.parent(manifest), module)
    if not module or not path.is_file(module) then error("Missing project module: " .. tostring(module), 0) end
  end

  local log_root = path.join(root, "Saved/Logs/CardReader")
  local tag = os.date("%Y%m%d-%H%M%S") .. ("-%08x"):format(math.random(0, 0x7fffffff))
  local log = path.join(log_root, tag .. ".log")
  -- Explicit map and game mode: a saved crowd/demo startup map must not take over.
  local map = "/Engine/Maps/Templates/Template_Default?game=/Script/OpenKoikatsu.OpenKoikatsuGameMode"
  local args = stage_exe and { exe, map, "-D3D12", "-SM6" } or { exe, project, map, "-game" }
  for _, x in ipairs({ "-windowed", "-ResX=" .. width, "-ResY=" .. height, "-NoSplash", "-nop4", "-abslog=" .. (stage_exe and street_stage.ue_path(stage_exe, log) or log) }) do args[#args + 1] = x end
  local stage_env = {}
  if stage_exe and not o.dryrun then
    local extra
    extra, stage_env = street_stage.packaged_launch(root, stage_exe)
    for _, x in ipairs(extra) do args[#args + 1] = x end
  end
  -- The game shows the DreamGUI reader screen by default; -LegacyReader goes back to the old UMG gallery (kept for
  -- comparison until the new screen is complete). Passing -LegacyReader after -- works the same and is not added twice.
  if o.legacyreader then
    local given = false
    for _, x in ipairs(o.passthrough) do if x:lower() == "-legacyreader" then given = true end end
    if not given then args[#args + 1] = "-LegacyReader" end
  end
  -- The DreamGUI screen runs with RDG's parallel pass execution off from startup (2026-11-19, the reader's open GPU page
  -- fault, Docs/CARD_READER_DREAMGUI.md): opening different cards with a few seconds between crashed within 5-17 cards
  -- every time it was on; off from the command line, three runs of 40, 60 and 60 cards did not. Turned off from code when
  -- the reader screen opened instead, it still crashed (card 6), so it has to be set before the engine renders.
  -- It holds for the whole process and is never given back: the one-on-one and the studio entered from the reader run
  -- serially too (set back and taken again while running, the reader crashed on card 4). -ParallelRDG keeps the
  -- engine's default.
  local legacy = o.legacyreader
  for _, x in ipairs(o.passthrough) do if x:lower() == "-legacyreader" then legacy = true end end
  if not legacy and not o.parallelrdg then
    args[#args + 1] = "-ini:Engine:[ConsoleVariables]:r.RDG.ParallelExecute=0"
  end
  -- 物理：旗標由遊戲在建立物理選單之前套用（OKCharacterController::ApplyStartupPhysicsBackend），選單才會顯示
  -- 真正在跑的那一項。用 -ExecCmds 不行：指令在選單建好之後才跑，解算器已是 Verlet 而選單還寫著「依元件」。
  local physics = (o.physics or os.getenv("OK_READER_PHYSICS") or "verlet"):lower()
  if not PHYSICS[physics] then
    local names = {}
    for k in pairs(PHYSICS) do names[#names + 1] = k end
    table.sort(names)
    error(("-Physics must be one of: %s"):format(table.concat(names, ", ")), 0)
  end
  args[#args + 1] = "-OKPhysics=" .. physics
  -- The reader screen's pages (Docs/READER_DATA_DRIVEN_PAGES_DESIGN.md): a stage has only the Config it was staged with,
  -- so the checkout's file is named; the editor target reads the same file without it.
  -- A -ReaderPages= given after "--" (reader_launch extra) is the one used: the screen reads the first one on the
  -- command line, so the default is left out rather than put in front of it.
  local own_pages = false
  for _, x in ipairs(o.passthrough) do if x:lower():find("^%-readerpages=") then own_pages = true end end
  if not own_pages then args[#args + 1] = "-ReaderPages=" .. (path.join(root, "Config/ReaderEditor/pages.json"):gsub("\\", "/")) end
  for _, x in ipairs(o.passthrough) do args[#args + 1] = x end
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
    OK_MIND_DLL = path.is_file(mind_dll) and (mind_dll:gsub("/", "\\")) or false, OK_AUTO_3D = card and "1" or "0", OK_AUTO_CARD = card and path.name(card) or false, OK_CARD_DIRECTORY = cards ~= "" and cards_chosen and (cards:gsub("/", "\\")) or false,
    OK_CARD_DIRECTORY_DEFAULT = cards ~= "" and not cards_chosen and (cards:gsub("/", "\\")) or false,
    OK_WARM_PRIORITY = false,
    OK_CPU_SKIN = gpu and "0" or "1", OK_GPU_SKIN = gpu and "1" or "0", OK_SKELMESH = gpu and "1" or "0",
    OK_NOPOSE = false, OK_UE_ANIM = false, OK_HEAD_GPUSKIN = false }
  for k, v in pairs(stage_env) do env[k] = v end
  local saved = {}
  for k, v in pairs(env) do saved[k] = fs.getenv(k) or false; fs.setenv(k, v or nil) end
  local okv, pid = pcall(proc.spawn, args, { cwd = root })
  for k, v in pairs(saved) do fs.setenv(k, v or nil) end
  if not okv then error(pid, 0) end
  receipt.pid = pid
  instance.record_launch(pid, root)
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
  -- GPU 卡死（DXGI_ERROR_DEVICE_HUNG）之後視窗還在、通道還在聽，但不會再回應。這個啟動器照使用者的決定不自動
  -- 關任何東西（那是你的視窗），只告訴你怎麼看：ok_hang_check 會印出沒回應的行程、log 與 GPU dump 在哪、怎麼自己關。
  io.write("Stuck? Tools\\lua\\lua.exe Tools\\ok_hang_check.lua (or launch with -Watch to keep this window watching)\n")
  if o.watch then
    io.write("\n")
    local checker = { path.join(root, "Tools", "lua", "lua.exe"), path.join(root, "Tools", "ok_hang_check.lua"),
      "--watch", "--pid=" .. tostring(pid) }
    os.exit(proc.run(checker, { cwd = root, check = false }).code or 0)
  end
end

ok.main(main)
