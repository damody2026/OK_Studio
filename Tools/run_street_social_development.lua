-- StreetSocial development launcher (StreetSocial.cmd). Runs the newest staged build (Saved/StreetSocial/Build/*.stage)
-- unless -Executable is given; CrowdRoom*.stage lives there too but is the crowd room's build. Integrity (SHA256) checks
-- against receipt.json only run with -Strict: several agents rebuild shared data and stages at the same time, so the
-- default just needs the files to exist.
--
--   Tools\lua\lua.exe Tools\run_street_social_development.lua [-Control [-ControlPort N]] [-Clock HH:MM] [-SelfTest]
--     [-ValidateOnly] [-Strict] [-Executable EXE] [-SelectionFile JSON] [-MaleCard PNG] [-RetargetFile JSON]
--     [-RenderScale 100..200 (default 100)] [-Window WxH]  (window size, default 1920x1080; a smaller one leaves room for other work)
--     [-Editor]  (development: runs the map in the built editor with -game instead of a staged build; no cook needed)
--     [-GpuRig | -NoGpuRig]  (heroine poses from the GPU runtime rig, Docs/CROWD_ROOM100.md, or from her own solved banks)
--     [-GpuRigVerify N]  (also solve full banks and compare N frames of the rig with them: runtime.json "gpu_rig", rig.bin)
--     [-Sandbox NAME [-PortBase N] [-RulesDll DLL]] [-Exec "CMD,CMD"] [-Trace [CHANNELS]] [-GameArgs "-SWITCH ..."]
--     [-NoCloud]  (with -Sandbox: the sandbox's DeepSeek / Alibaba Cloud keys emptied for the run; no cloud calls)
--     [-Heroine N|PNG]  (test: only the male and this one heroine, N counting from 1 in the selection, nobody else
--       loaded; a save made with the full roster is not for it)
--     [-Inspect [N]]  (straight into the inspection room with heroine N: her alone in an empty room, the camera round her
--       by the arrow keys, wheel nearer/farther, PageUp/PageDown another heroine, End back to the street)
-- -Control without -Sandbox runs as -Sandbox Control on this checkout's own ports; -MainSave keeps it on the main save.
-- -Sandbox runs a second game beside one already playing from this checkout without touching it: its own ports
-- (-PortBase, default 48060: TTS N, ASR N+1, control N+10), its own save, voice settings and free-talk logs in
-- Saved/StreetSocial/Sandbox/NAME/ (copied from the main save the first time), voice servers started for it only (the
-- other game's are not stopped), and its own copies of the rules / mind DLLs (no cargo build of Tools/ok-rules, which
-- the other game hot-reloads). Identity migration of the shared saves is skipped.
-- Option names are case-insensitive and may also be written --control, --control-port, ... (StreetSocial.cmd passes
-- its arguments here unchanged).
--
-- Ports and voice servers follow this checkout's local-instance.json (Tools/ok_instance.lua): another clone on the same
-- machine runs its own game on its own ports, and only servers started from this checkout's Build/ are stopped.
local ok = require "ok"
local json, path, proc, hash, util = ok.json, ok.path, ok.proc, ok.hash, ok.util
local fs = require "okfs"
local instance = require "ok_instance"
local player_settings = require "street_player_settings"

local SWITCHES = { validateonly = true, selftest = true, strict = true, control = true, mainsave = true, editor = true, nogpurig = true, gpurig = true, city = true, citysource = true, nocloud = true }
local VALUES = { selectionfile = true, malecard = true, retargetfile = true, renderscale = true, executable = true,
  controlport = true, clock = true, window = true, sandbox = true, portbase = true, rulesdll = true, exec = true, trace = true, gpucachedir = true,
  gameargs = true, gpurigverify = true, heroine = true, patchdir = true }

local function parse(argv)
  local o, i = {}, 1
  while i <= #argv do
    local raw = argv[i]
    local name, inline = raw:match("^%-%-?([%w%-]+):(.*)$")
    if not name then name = raw:match("^%-%-?([%w%-]+)$") end
    if not name then error("unexpected argument: " .. raw, 0) end
    local key = name:gsub("%-", ""):lower()
    -- -Inspect [N]: straight into the inspection room with heroine N (1 when no number follows).
    if key == "inspect" then
      local n = inline or (argv[i + 1] and argv[i + 1]:match("^%d+$"))
      if n and not inline then i = i + 1 end
      o.inspect = tonumber(n) or 1
    elseif SWITCHES[key] then o[key] = true
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

local function say(s) io.write(s, "\n"); io.flush() end
local function sha(p) return hash.sha256_file(p):lower() end
local function exists(p) return p ~= nil and p ~= "" and path.exists(p) end
local function read_json(p) return json.decode(path.read_text(p)) end
local function tool(script, args) return proc.lua(path.join(ok.root, "Tools", script), args) end

-- Identity retargets (formerly an inline Lua block of the PowerShell launcher): check a request file, or inject it.
local function retarget(mode, request_path, manifest_path)
  local function quit(msg) error("Identity retarget file was rejected: " .. msg, 0) end
  local payload = json.decode(path.read_text(request_path))
  local rows
  if json.is_array(payload) then rows = payload
  elseif json.is_object(payload) and #json.keys(payload) == 1 and json.keys(payload)[1] == "identity_retargets" and json.is_array(payload.identity_retargets) then
    rows = payload.identity_retargets
  else quit("Identity retarget file must be a request array or an object with only identity_retargets") end
  if #rows < 1 or #rows > 10 then quit("Identity retarget file must contain 1 to 10 requests") end
  local function identity(v) return type(v) == "string" and #v == 69 and v:match("^apng%-[0-9a-f]+$") ~= nil end
  local clean, seen = {}, {}
  for _, row in ipairs(rows) do
    if not json.is_object(row) or #json.keys(row) ~= 3 or row.request_id == nil or row.old_id == nil or row.new_id == nil then
      quit("Identity retarget request must have only request_id, old_id, and new_id")
    end
    local request_id, old_id, new_id = row.request_id, row.old_id, row.new_id
    if type(request_id) ~= "string" or #request_id > 64 or not request_id:match("^[A-Za-z0-9_%-]+$") or request_id:sub(1, 8) == "session-" or seen[request_id] then
      quit("Identity retarget request_id is invalid or duplicated")
    end
    if not identity(old_id) or not identity(new_id) or old_id == new_id then quit("Identity retarget ids must be distinct apng- sha256 values") end
    seen[request_id] = true
    clean[#clean + 1] = json.object({ { "request_id", request_id }, { "old_id", old_id }, { "new_id", new_id } })
  end
  if mode == "check" then return end
  local manifest = json.decode(path.read_text(manifest_path))
  local roster = {}
  for _, item in ipairs(manifest.characters or {}) do roster[#roster + 1] = util.str(item.id == nil and "" or item.id) end
  local females = util.slice(roster, 2)
  for _, row in ipairs(clean) do
    if not util.contains_value(females, row.new_id) then quit("Identity retarget new_id is not a selected female") end
    if util.contains_value(roster, row.old_id) then quit("Identity retarget old_id still belongs to a selected actor") end
  end
  manifest.identity_retargets = clean
  path.write_text(manifest_path, json.encode(manifest, { ensure_ascii = false, indent = 2 }) .. "\n", { newline = "\n" })
end

-- -Strict: everything the receipt verified must still hash the same.
local function strict_checks(build)
  local function same(p, digest) return exists(p) and sha(p) == digest end
  local q = build.runtime_render_quality
  if q and (q.antialiasing_method ~= 1 or q.screen_percentage ~= 150 or not same(q.evidence, q.evidence_sha256)) then error("Verified anti-aliasing quality profile changed", 0) end
  if not build.passed or not build.new_map or build.female_count ~= 5 then error("StreetSocial verified receipt is required", 0) end
  if build.material_manifest and not same(build.material_manifest, build.material_manifest_sha256) then error("Verified common material manifest changed", 0) end
  if build.runtime_display_profile and not same(build.runtime_display_profile.lut, build.runtime_display_profile.sha256) then error("Verified CardReader display LUT changed", 0) end
  if build.runtime_private_high_model and build.runtime_interaction_mode ~= "in_process" then
    if not same(build.high_interaction_host, build.high_interaction_host_sha256) then error("Verified CardReader interaction host changed", 0) end
    if not same(build.high_interaction_module, build.high_interaction_module_sha256) then error("Verified CardReader interaction module changed", 0) end
    for _, d in ipairs(read_json(build.high_interaction_host).dependencies or {}) do
      if not same(d.path, d.sha256) then error("Verified frozen CardReader dependency changed", 0) end
    end
  end
  if build.runtime_interaction_watergun or build.runtime_interaction_full_catalogue then
    local f = build.interaction_features_evidence
    if not f.passed or not same(f.evidence, f.sha256) then error("Verified interaction watergun/catalogue evidence changed", 0) end
  end
  if build.runtime_interaction_mode == "in_process" and not same(build.reader_interaction_evidence, build.reader_interaction_evidence_sha256) then
    error("Verified shared interaction acceptance changed", 0)
  end
end

local function strict_inputs(build)
  local function same(p, digest) return exists(p) and sha(p) == digest end
  if build.executable_sha256 and sha(build.executable) ~= build.executable_sha256 then error("Verified StreetSocial executable changed", 0) end
  if build.patch_file_sha256 then
    local want, have = json.keys(build.patch_file_sha256), {}
    for _, n in ipairs(path.list(build.patch)) do if n:lower():match("%.pak$") then have[#have + 1] = n end end
    table.sort(want); table.sort(have)
    if #want ~= #have then error("Verified runtime patch set changed", 0) end
    for i, n in ipairs(want) do
      if n ~= have[i] then error("Verified runtime patch set changed", 0) end
      if path.name(n) ~= n then error("Invalid runtime patch filename", 0) end
      if sha(path.join(build.patch, n)) ~= build.patch_file_sha256[n] then error("Verified runtime patch changed", 0) end
    end
  end
  if build.runtime_invitations and not same(build.invitations_catalogue, build.invitations_sha256) then error("Shared invitation catalogue changed since validation", 0) end
  if build.runtime_dialogue_context then
    if not same(build.relationships_catalogue, build.relationships_sha256) then error("Shared relationship dialogue changed since validation", 0) end
    local pack = read_json(build.relationships_catalogue)
    local base = path.parent(path.parent(build.relationships_catalogue))
    for _, name in ipairs(json.keys(pack.source_voice_sha256 or json.object({}))) do
      if not same(path.join(base, name), pack.source_voice_sha256[name]) then error("Shared relationship voice changed since validation", 0) end
    end
  end
  local packs = {}
  local function pack(flag, name, p, h) if flag then packs[#packs + 1] = { name = name, path = p, hash = h } end end
  pack(build.runtime_presentation, "locomotion", build.locomotion_manifest, build.locomotion_manifest_sha256)
  pack(build.runtime_phone_use, "phone", build.phone_manifest, build.phone_manifest_sha256)
  pack(build.runtime_npc_drink, "drink", build.drink_manifest, build.drink_manifest_sha256)
  pack(build.runtime_npc_selfie, "selfie", build.selfie_manifest, build.selfie_manifest_sha256)
  pack(build.runtime_npc_groom, "groom", build.groom_manifest, build.groom_manifest_sha256)
  pack(build.runtime_touch_body_reaction, "touch", build.touch_manifest, build.touch_manifest_sha256)
  for _, p in ipairs(packs) do
    if not same(p.path, p.hash) then error("Shared " .. p.name .. " manifest changed since validation", 0) end
    for _, a in ipairs(read_json(p.path).actions or {}) do
      if not same(path.join(path.parent(p.path), a.file), a.sha256) then error("Shared " .. p.name .. " animation changed since validation", 0) end
    end
  end
end

-- Newest StreetSocial stage executable (CrowdRoom*.stage is the crowd room's).
local function newest_stage(root)
  local dir, best, best_time = path.join(root, "Saved/StreetSocial/Build"), nil, -1
  if not path.is_dir(dir) then return nil end
  for _, n in ipairs(path.list(dir)) do
    if n:lower():match("%.stage$") and not n:lower():match("^crowdroom") then
      local exe = path.join(dir, n, "Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe")
      local t = path.mtime(exe)
      if t and t > best_time then best, best_time = exe, t end
    end
  end
  return best
end

local function main()
  local o = parse(arg)
  -- A controlled run is a test: it never touches the player's save, even for a moment (loading rewrites it). It takes
  -- the sandbox Control on this checkout's own ports, so ok-game-mcp finds it. -MainSave is for when the save is the test.
  if o.control and not o.sandbox and not o.mainsave then
    o.sandbox = "Control"
    o.portbase = o.portbase or tostring(instance.ports(ok.root).base)
  end
  local root = ok.root
  local build, launch
  if o.strict then
    local receipt = path.join(root, "Saved/StreetSocial/Build/receipt.json")
    if not path.is_file(receipt) then error("StreetSocial Development has not passed build/runtime validation yet", 0) end
    build = read_json(receipt)
  else
    -- Saved/ is disposable: everything the launch needs comes from Content (Launch/runtime.json); the executable is the
    -- newest stage, rebuilt from Content + Source when none is left.
    launch = read_json(path.join(root, "Content/IndependentResources/StreetSocialData/Launch/runtime.json"))
    -- -PatchDir: another runtime patch folder (Tools/rebuild_street_social_patch.lua --output) instead of the shared one, e.g.
    -- a stage whose global shaders changed: the shared patch's RuntimeGlobalShaderPatch-*_P.pak would override its base's.
    build = { executable = "", patch = o.patchdir and path.abs(o.patchdir) or path.join(root, launch.patch), catalogue = path.join(root, launch.catalogue),
      material_manifest = path.join(root, launch.materials), runtime_render_quality = launch.render_quality }
    if o.editor then o.executable = path.join(ok.engine_root(), "Engine/Binaries/Win64/UnrealEditor.exe") end
    if not o.executable then
      local latest = newest_stage(root)
      if not latest then
        say("No StreetSocial build under Saved/: rebuilding it from Content + Source (this takes a while)...")
        tool("rebuild_street_social_runtime.lua", { "--tag", "StreetAuto" .. os.date("%Y%m%d%H%M") })
        latest = newest_stage(root)
        if not latest then error("StreetSocial rebuild did not produce a stage", 0) end
      end
      o.executable = latest
    end
    build.executable = path.abs(o.executable)
    say("StreetSocial build: " .. build.executable)
    -- A stage from a package (Tools/package_street_social.lua) comes without its junctions into this folder's Content
    -- (IndependentResources, and KKPreview once the original data is restored): made here when missing.
    -- Only a stage's own game (…/X.stage/Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe): -Editor runs the
    -- engine's UnrealEditor.exe, whose Content is the engine's.
    if build.executable:lower():match("%.stage/windows/openkoikatsu/binaries/win64/[^/]+%.exe$") then
      local content = path.join(path.parent(path.parent(path.parent(build.executable))), "Content")
      for _, name in ipairs({ "IndependentResources", "KKPreview" }) do
        local link, target = path.join(content, name), path.join(root, "Content", name)
        if path.is_dir(content) and not path.exists(link) and path.is_dir(target) then
          local made = proc.run({ "cmd", "/c", "mklink", "/J", (link:gsub("/", "\\")), (target:gsub("/", "\\")) }, { quiet = true })
          say((made.ok and "Linked " or "Could not link ") .. link .. " -> " .. target)
        end
      end
    end
    -- The runtime material shader library and audio settings ship as a patch beside the stage; rebuild it when gone.
    if not path.exists(build.patch) then
      say("No StreetSocial runtime patch under Saved/: rebuilding it from Content...")
      tool("rebuild_street_social_patch.lua")
      if not path.exists(build.patch) then error("StreetSocial patch rebuild failed", 0) end
    end
    -- The player's own roster wins; otherwise the default heroines from Content (made absolute for the selection tool).
    local default_selection = path.join(root, "Saved/StreetSocial/heroines.json")
    if not o.selectionfile and not path.exists(default_selection) then
      local roster = read_json(path.join(root, launch.roster))
      path.mkdir(path.join(root, "Saved/StreetSocial"), true)
      local cards = json.array({})
      for _, c in ipairs(roster.cards) do cards[#cards + 1] = path.abs(path.join(root, c)) end
      path.write_text(default_selection, json.encode(json.object({ { "cards", cards } }), { indent = 2, ensure_ascii = false }))
      o.selectionfile = default_selection
    end
    if not o.malecard then o.malecard = path.join(root, launch.male_card) end
  end
  local render_scale = tonumber(o.renderscale or "0")
  if not render_scale or render_scale < 0 or render_scale > 200 or (render_scale > 0 and render_scale < 100) then
    error("RenderScale must be 0 (default, 100 percent), or 100..200 percent", 0)
  end
  if o.strict then strict_checks(build) end
  o.selectionfile = o.selectionfile or path.join(root, "Saved/StreetSocial/heroines.json")
  o.malecard = o.malecard or path.join(root, "output/StreetSocialAPNG/Male01.png")
  -- -Heroine: the male and one heroine only (user, 2026-11-02: a test of one scene need not wait for every other girl).
  if o.heroine then
    local n, card = tonumber(o.heroine), nil
    if n then
      local cards = read_json(o.selectionfile).cards or {}
      card = cards[n]
      if not card then error(("-Heroine %d: the selection has %d heroines"):format(n, #cards), 0) end
    else card = path.abs(o.heroine) end
    local only = path.join(root, "Saved/StreetSocial/heroine-only" .. (o.sandbox and ("-" .. o.sandbox) or "") .. ".json")
    path.mkdir(path.parent(only), true)
    path.write_text(only, json.encode(json.object({ { "cards", json.array({ card }) } }), { indent = 2, ensure_ascii = false }))
    o.selectionfile = only
    say("Heroine only: " .. card)
  end
  -- The patch is not an input check outside -Strict: it was rebuilt above when missing (it carries the material roots).
  -- The original dialogue catalogue is optional (original game data, Tools/original_data.lua): without it, free talk only.
  local inputs = { build.executable, o.selectionfile, o.malecard }
  if o.strict then inputs[#inputs + 1] = build.patch end
  for _, p in ipairs(inputs) do if not exists(p) then error("Missing StreetSocial input: " .. tostring(p), 0) end end
  if o.strict then strict_inputs(build) end
  if o.retargetfile then
    if not path.is_file(o.retargetfile) then error("Missing identity retarget file: " .. o.retargetfile, 0) end
    local size = path.size(o.retargetfile)
    if size <= 0 or size > 65536 then error("Identity retarget file must be 1 to 65536 bytes: " .. o.retargetfile, 0) end
    retarget("check", o.retargetfile)
  end
  if o.retargetfile and o.selftest then error("Identity retarget file cannot be combined with -SelfTest", 0) end
  if o.validateonly then
    if o.retargetfile then say("Identity retarget file accepted: " .. o.retargetfile) end
    say("Verified new StreetSocial map: " .. build.executable)
    return
  end

  local output = path.join(root, "Saved/StreetSocial/Play-" .. os.date("%Y%m%dT%H%M%S"))
  local suffix = 0
  while path.exists(output .. (suffix > 0 and ("-" .. suffix) or "")) do suffix = suffix + 1 end
  output = output .. (suffix > 0 and ("-" .. suffix) or "")
  path.mkdir(output, true)
  local manifest = path.join(output, "selection.json")
  local materials = build.material_manifest or path.join(root, "Saved/Crowd/RuntimeSharedMaterial-R1145.json")
  -- Saved/ is disposable: when the material receipt is gone, derive it from its tag (the materials live in Content).
  if not path.exists(materials) then
    local tag = path.stem(materials):gsub("^RuntimeSharedMaterial%-", "")
    if not path.exists(path.join(root, "Content/IndependentResources/RuntimeMaterials", tag)) then error("Runtime materials missing: " .. tag, 0) end
    materials = path.join(output, "materials.json")
    path.write_text(materials, json.encode(json.object({ { "schema", 1 }, { "passed", true }, { "runtime_reveal_supported", true },
      { "root", "/Game/IndependentResources/RuntimeMaterials/" .. tag }, { "derived", true } }), { indent = 2 }))
  end
  local sel = proc.lua(path.join(root, "Tools/prepare_street_social_selection.lua"), { "--male", o.malecard, "--selection", o.selectionfile,
    "--catalogue", build.catalogue, "--materials", materials, "--output", manifest })
  if not sel.ok then error("StreetSocial APNG selection validation failed", 0) end
  if o.retargetfile then retarget("inject", o.retargetfile, manifest) end
  -- The editor has no cooked shader library; the crowd runtime then draws with the editor's own material resources.
  if o.editor then
    local m = read_json(manifest)
    m.editor_common_materials = true
    path.write_text(manifest, json.encode(m, { ensure_ascii = false, indent = 2 }) .. "\n", { newline = "\n" })
  end
  -- -GpuRig: poses from the GPU runtime rig (off by default until the street is checked with it).
  if o.gpurig and not o.nogpurig then
    local m = read_json(manifest)
    m.gpu_rig = true
    path.write_text(manifest, json.encode(m, { ensure_ascii = false, indent = 2 }) .. "\n", { newline = "\n" })
  end
  -- -GpuRigVerify N: the rig, full banks as well, and N frames of its rows compared with them (runtime.json "gpu_rig").
  if o.gpurigverify then
    local m = read_json(manifest)
    m.gpu_rig = true
    m.gpu_rig_verify = tonumber(o.gpurigverify) or 0
    path.write_text(manifest, json.encode(m, { ensure_ascii = false, indent = 2 }) .. "\n", { newline = "\n" })
  end
  -- -NoGpuRig: each heroine's poses from her own solved banks again (the GPU rig's shaders come from the patch's global
  -- shader pak; a stage older than the rig has none).
  if o.nogpurig then
    local m = read_json(manifest)
    m.gpu_rig = false
    path.write_text(manifest, json.encode(m, { ensure_ascii = false, indent = 2 }) .. "\n", { newline = "\n" })
  end
  -- Replaced heroine cards (StreetSocialData/identity_aliases.json): the live game and every save slot move to the new
  -- ids before the game opens them (a no-op when no save names an old id).
  if not o.selftest and not o.sandbox and not tool("street_identity_migrate.lua", {}).ok then error("Identity alias migration failed", 0) end
  -- The player's settings, keys included, are one file: Saved/StreetSocial/player.json (Tools/street_player_settings.lua,
  -- Docs/API_KEYS.md); the older voice / microphone / DeepSeek files are read into it once. Saved/ is disposable, so
  -- it is kept at %LOCALAPPDATA%\OpenKoikatsu\player.json too and put back from there when Saved/ was cleared.
  local user_dir = os.getenv("LOCALAPPDATA") and path.join(os.getenv("LOCALAPPDATA"), "OpenKoikatsu")
  local main_settings = path.join(root, "Saved/StreetSocial/player.json")
  path.mkdir(path.join(root, "Saved/StreetSocial"), true)
  if user_dir and not path.is_file(main_settings) and path.is_file(path.join(user_dir, "player.json")) then
    pcall(path.copy, path.join(user_dir, "player.json"), main_settings); say("Restored player.json from " .. user_dir)
  end
  do
    local _, notes = player_settings.migrate(path.join(root, "Saved/StreetSocial"))
    if #notes > 0 then say("Player settings: moved " .. table.concat(notes, ", ") .. " into " .. main_settings) end
  end
  if user_dir then path.mkdir(user_dir, true); pcall(path.copy, main_settings, path.join(user_dir, "player.json")) end
  -- Sandbox: the save (and what lives beside it: voice settings, free-talk logs) moves to the sandbox folder.
  local sandbox
  if o.sandbox then
    if not o.sandbox:match("^[%w_%-]+$") then error("-Sandbox takes a name of letters, digits, - and _", 0) end
    sandbox = path.join(root, "Saved/StreetSocial/Sandbox", o.sandbox)
    path.mkdir(sandbox, true)
    for _, name in ipairs({ "relationships.json", "player.json", "phone.json", "free-talk-log.json", "free-talk-memory.json" }) do
      local main_file, own = path.join(root, "Saved/StreetSocial", name), path.join(sandbox, name)
      if not path.exists(own) and path.is_file(main_file) then path.copy(main_file, own) end
    end
    local m = json.decode(path.read_text(manifest))
    m.save_path = (path.join(sandbox, "relationships.json"):gsub("/", "\\"))
    path.write_text(manifest, json.encode(m, { ensure_ascii = false, indent = 2 }))
    player_settings.migrate(sandbox)
    say("Sandbox " .. o.sandbox .. ": save and settings in " .. sandbox)
  end
  -- The settings this run uses (the sandbox's own when there is one).
  local settings_file = sandbox and path.join(sandbox, "player.json") or main_settings
  -- -NoCloud: no DeepSeek or Alibaba Cloud call this run (tests while the cloud is off limits). The sandbox's keys are
  -- emptied after the migration above, which otherwise refills an empty key from %LOCALAPPDATA%\OpenKoikatsu every launch
  -- (an emptied sandbox key came back at the next start and the heroines' mind called DeepSeek). The shared copies there
  -- are left alone, so the keys come back once the run is made without -NoCloud and the sandbox file is restored.
  if o.nocloud then
    if not sandbox then error("-NoCloud needs -Sandbox (it empties the run's own player.json, never the main one)", 0) end
    local p = json.decode(path.read_text(settings_file))
    local cleared = 0
    for _, name in ipairs({ "deepseek", "aliyun" }) do
      if json.is_object(p[name]) and type(p[name].api_key) == "string" and p[name].api_key ~= "" then p[name].api_key = ""; cleared = cleared + 1 end
    end
    if cleared > 0 then
      local tmp = settings_file .. ".nocloud"
      path.write_text(tmp, json.encode(p, { ensure_ascii = false, indent = 2 }))
      os.remove(settings_file); assert(os.rename(tmp, settings_file))
    end
    say("No cloud: " .. cleared .. " key(s) emptied in " .. settings_file .. "; the heroines' mind and the voices stay local")
  end
  local settings = player_settings.read(settings_file)

  -- This checkout's ports and voice servers (local-instance.json, Tools/ok_instance.lua).
  local ports = instance.ports(root)
  if sandbox then ports = instance.ports_at(math.tointeger(tonumber(o.portbase or "48060")) or error("-PortBase takes a number", 0), ports.voice) end
  local control_port = tonumber(o.controlport) or ports.street_control
  -- Voice servers (ok-tts speech, ok-asr voice input) live and die with the game: a copy this checkout left from an
  -- earlier run is stopped here, and the fresh ones start after the game with --parent-pid so they exit when it does.
  local voice = ports.voice and not o.selftest
  if not ports.voice then say("local-instance.json voice=false: no ok-tts / ok-asr from this checkout (built-in voices, no voice input)") end
  local servers = {}
  local asr_endpoint, tts_endpoint = "http://127.0.0.1:" .. ports.asr, "http://127.0.0.1:" .. ports.tts
  local song_endpoint = "http://127.0.0.1:" .. ports.song
  -- Without servers of its own (voice=false), a checkout may speak through another one's ok-tts (testing the voices on
  -- E with C's server): OK_TTS_ENDPOINT / OK_ASR_ENDPOINT / OK_SONG_ENDPOINT from the environment win then.
  if not voice then
    tts_endpoint = fs.getenv("OK_TTS_ENDPOINT") or tts_endpoint
    asr_endpoint = fs.getenv("OK_ASR_ENDPOINT") or asr_endpoint
    song_endpoint = fs.getenv("OK_SONG_ENDPOINT") or song_endpoint
  end
  if voice then
    if not sandbox then instance.stop_own_voice_servers(root) end
    local v = settings.voice
    -- Free-talk replies are always spoken through ok-tts, so it starts in built-in voice mode too; "off" (no voices)
    -- starts none. voice_mode "cloud" with an Alibaba Cloud key: ok-tts makes the lines in the cloud and loads no model
    -- (it reads the key from player.json). Otherwise its Base model is the one chosen in the voice panel
    -- (tts_base_size: 1.7B by default, 0.6B saves about 1 GB of VRAM); a model not on this machine is downloaded by
    -- ok-tts on its first start (Build/ok-tts/models, not versioned).
    local tts = path.join(root, "Build/ok-tts/ok-tts.exe")
    local tts_args = { "serve", "--port", tostring(ports.tts), "--settings", settings_file }
    local size = v.tts_base_size
    if size == "1.7B" or size == "0.6B" then tts_args[#tts_args + 1] = "--base-size"; tts_args[#tts_args + 1] = size end
    if v.voice_mode == "off" then say("Voices are off (settings): no TTS server")
    elseif path.is_file(tts) then servers[#servers + 1] = { name = "TTS", file = tts, args = tts_args }
    else say("TTS server not found; built-in voice will be used: " .. tts) end
    -- Free-talk voice input: player.json asr.device may name the microphone (part of the input device name);
    -- otherwise the Windows default recording device is used; asr.mode "cloud" with a key recognizes in the cloud.
    -- ok-asr writes its own log (Build/ok-asr/logs/ok-asr.log).
    -- A saved asr.endpoint names someone else's server and is used only without one of our own: the server started here
    -- listens on this instance's port, and E launched with C's saved 47861 shared C's ok-asr (and its mute) with C's game.
    local asr = path.join(root, "Build/ok-asr/ok-asr.exe")
    if not path.is_file(asr) and type(settings.asr.endpoint) == "string" and settings.asr.endpoint ~= "" then asr_endpoint = settings.asr.endpoint end
    if path.is_file(asr) then
      servers[#servers + 1] = { name = "ASR", file = asr, args = { "serve", "--port", tostring(ports.asr), "--settings", settings_file } }
    else say("ASR server not found; voice input unavailable: " .. asr) end
    -- Heroine songs (Tools/ok-song; its ok-song.json beside the exe says where the model stages run). Optional: without
    -- it the game simply never offers a song.
    local song = path.join(root, "Build/ok-song/ok-song.exe")
    if path.is_file(song) then servers[#servers + 1] = { name = "Song", file = song, args = { "serve", "--port", tostring(ports.song) } }
    else say("Song server not found; heroines will not sing: " .. song) end
  end

  -- Heroine mind (Tools/ok-mind, cargo build --release): the game loads a copy, so cargo can rebuild while it runs.
  -- Without the DLL the street keeps its old behaviour.
  -- Built here like the rules (a no-op when up to date): after the 11-09 integration the copy was the one built before
  -- it, which still looked for the retired deepseek.json, and every reply failed "no_api_key" (R6-187).
  local mind_crate = path.join(root, "Tools/ok-mind")
  local mind_source = path.join(mind_crate, "target/release/ok_mind.dll")
  local mind_dll = path.join(sandbox or path.join(root, "Saved/StreetSocial/Build"), "ok-mind/ok_mind.dll")
  if proc.which("cargo") then
    local r = proc.run({ "cargo", "build", "--release", "--quiet", "-j", "8" }, { cwd = mind_crate, capture = true })
    if not r.ok then say("Heroine mind build failed; using the previous build if there is one") end
  end
  if path.is_file(mind_source) then
    path.mkdir(path.parent(mind_dll), true)
    local copied, err = pcall(path.copy, mind_source, mind_dll)
    if not copied then say("Heroine mind DLL in use, keeping the previous copy: " .. tostring(err)) end
  end
  -- Game rules (Tools/ok-rules): required. Built here when cargo is available (a no-op when up to date); the game loads
  -- a copy so cargo can rebuild while it runs, and ok.StreetRules.Reload (or ok-game-mcp game_call /rules reload) swaps it in.
  local rules_crate = path.join(root, "Tools/ok-rules")
  -- -RulesDll (sandbox): a rules build of its own (e.g. made with another CARGO_TARGET_DIR), so testing new rules never
  -- swaps the DLL the other game hot-reloads.
  local rules_source = (sandbox and o.rulesdll) and path.abs(o.rulesdll) or path.join(rules_crate, "target/release/ok_rules.dll")
  local rules_dll = path.join(sandbox or path.join(root, "Saved/StreetSocial/Build"), "ok-rules/ok_rules.dll")
  if proc.which("cargo") and not sandbox then
    local r = proc.run({ "cargo", "build", "--release", "--quiet", "-j", "8" }, { cwd = rules_crate, capture = true })
    if not r.ok then say("Game rules build failed; using the previous build if there is one") end
  end
  if path.is_file(rules_source) then
    path.mkdir(path.parent(rules_dll), true)
    local copied, err = pcall(path.copy, rules_source, rules_dll)
    if not copied then say("Game rules DLL in use, keeping the previous copy: " .. tostring(err)) end
  else say("Game rules DLL not built (cargo build --release in Tools/ok-rules); the game will show the error and quit: " .. rules_source) end
  -- Conversation presentation (Tools/ok-story, galgame dialog box / portrait / shots): optional, a copy like the rules.
  local story_crate = path.join(root, "Tools/ok-story")
  local story_source = path.join(story_crate, "target/release/ok_story.dll")
  local story_dll = path.join(root, "Saved/StreetSocial/Build/ok-story/ok_story.dll")
  if proc.which("cargo") then
    local r = proc.run({ "cargo", "build", "--release", "--quiet", "-j", "8" }, { cwd = story_crate, capture = true })
    if not r.ok then say("Conversation presenter build failed; using the previous build if there is one") end
  end
  if path.is_file(story_source) then
    path.mkdir(path.parent(story_dll), true)
    local copied, err = pcall(path.copy, story_source, story_dll)
    if not copied then say("Conversation presenter DLL in use, keeping the previous copy: " .. tostring(err)) end
  end

  -- The game reads these at start; set only for the processes started below (this launcher's own environment).
  local env = {
    OK_BUILTIN_RESOURCES = path.join(root, "Content/IndependentResources/v1"),
    OK_RULES_DLL = path.is_file(rules_dll) and rules_dll or "",
    OK_RULES_SOURCE_DLL = rules_source,
    OK_RULES_TUNING = path.join(root, "Content/IndependentResources/StreetSocialData/rules"),
    OK_STORY_DLL = path.is_file(story_dll) and story_dll or "",
    OK_STORY_DATA = path.join(root, "Content/IndependentResources/Story"),
    -- Free talk: staged builds cannot see the project Saved/Content folders, so pass absolute paths. The DeepSeek key
    -- is the "deepseek" section of the player's settings.
    OK_FREE_TALK_SETTINGS = settings_file,
    OK_FREE_TALK_PERSONAS = path.join(root, "Content/IndependentResources/StreetSocialData/free_talk_personas.json"),
    OK_ASR_ENDPOINT = asr_endpoint,
    -- The launcher started ok-tts on this checkout's port; it wins over an endpoint saved in player.json.
    OK_TTS_ENDPOINT = tts_endpoint,
    OK_SONG_ENDPOINT = song_endpoint,
    -- The game saves the microphone chosen in its settings here (asr.device); the next launch passes it to ok-asr.
    OK_ASR_SETTINGS = settings_file,
    OK_ASR_SERVER = path.join(root, "Build/ok-asr/ok-asr.exe"),
    OK_MIND_DLL = path.is_file(mind_dll) and mind_dll or "",
    -- The build the mind's hot reload watches (ok-game-mcp game_call /mind reload).
    OK_MIND_SOURCE_DLL = mind_source,
    -- -NoCloud: the game, the heroines' mind and the voice servers take no cloud path at all, whatever key they find.
    OK_NO_CLOUD = o.nocloud and "1" or "",
  }
  -- Paths in Windows form; the voice endpoints are URLs ("http://127.0.0.1:47861") and stay as they are.
  for k, v in pairs(env) do
    if v == "" then fs.setenv(k, nil)
    elseif v:match("^%a[%w+.-]*://") then fs.setenv(k, v)
    else fs.setenv(k, (v:gsub("/", "\\"))) end
  end

  local win_w, win_h = (o.window or "1920x1080"):match("^(%d+)[xX](%d+)$")
  if not win_w then error("-Window takes WxH, e.g. 1280x720", 0) end
  -- -City: the university city in place of the built street (Docs/STREET_CITY_PLACES_INVENTORY_20261103.md).
  -- -City plays the streamed map once it is in the project; -CitySource the whole map it is made from (the road bake needs it).
  -- Since 2026-11-13 the university city is the only map: the old built street (/Game/Scenes/StreetSocial) is not played.
  o.city = true
  if o.citysource then o.city = true end
  local city_map = (not o.citysource and path.exists(path.join(root, "Content/UniversityCity/Maps/UniversityCityWP.umap"))) and "UniversityCityWP" or "UniversityCity"
  local map = o.city and ("/Game/UniversityCity/Maps/" .. city_map .. "?game=/Script/OpenKoikatsu.OKCrowdGameMode") or "/Game/Scenes/StreetSocial/StreetSocial"
  local game = { build.executable, map, "-D3D12", "-SM6", "-windowed", "-ResX=" .. win_w, "-ResY=" .. win_h, "-WinX=40", "-WinY=40",
    "-StreetSocialManifest=" .. manifest }
  -- The editor reads the project's uncooked content: the project goes first, and the cooked patch is not mounted.
  if o.editor then table.insert(game, 2, path.join(root, "OpenKoikatsu.uproject")); game[#game + 1] = "-game"
  elseif path.exists(build.patch) then game[#game + 1] = "-pakdir=" .. build.patch end
  if o.city then game[#game + 1] = "-StreetCity" end
  game[#game + 1] = "-abslog=" .. path.join(output, "game.log")
  game[#game + 1] = "-RuntimeGpuCacheMiB=4096"
  -- The GPU rig's shaders are verified at startup only when asked for (OKGpuRig.cpp): with gpu_rig on, the patch has them.
  if read_json(manifest).gpu_rig then game[#game + 1] = "-OKGpuRig" end
  -- -GpuCacheDir <dir>: another runtime GPU pose cache (default %LOCALAPPDATA%, shared by every checkout).
  if o.gpucachedir then game[#game + 1] = "-RuntimeGpuCacheDir=" .. o.gpucachedir end
  local q = build.runtime_render_quality
  local execs = {}
  if q then
    -- 100% unless -RenderScale asks for more (user 2026-11-14): the verified 150% rendered 5760x2962 in a maximised 4K
    -- window, 48-82 FPS against 99-105 at 100%.
    local scale = render_scale > 0 and render_scale or 100
    execs[#execs + 1] = ("r.AntiAliasingMethod %s,r.ScreenPercentage %s"):format(util.str(q.antialiasing_method), util.str(scale))
  end
  -- Profiling (development): -Exec "stat dumphitches,t.HitchFrameTimeThreshold 60" runs console commands at start;
  -- -Trace records an Unreal Insights trace (default channels default,cpu,gpu,frame,bookmark) to trace.utrace beside game.log.
  if o.exec then execs[#execs + 1] = o.exec end
  -- -GameArgs "-A -B=1": more command-line switches for the game itself (development diagnostics such as -RuntimeFaceDiag).
  if o.gameargs then for a in tostring(o.gameargs):gmatch("%S+") do game[#game + 1] = a end end
  if #execs > 0 then game[#game + 1] = "-ExecCmds=" .. table.concat(execs, ",") end
  if o.trace then
    game[#game + 1] = "-trace=" .. ((o.trace == true or o.trace == "") and "default,cpu,gpu,frame,bookmark" or o.trace)
    game[#game + 1] = "-tracefile=" .. path.join(output, "trace.utrace"); game[#game + 1] = "-statnamedevents"
  end
  if o.selftest then for _, a in ipairs({ "-StreetSocialSelfTest", "-unattended", "-RenderOffscreen" }) do game[#game + 1] = a end end
  -- The control channel (http://127.0.0.1:<port>: state, say, click, key, navigate, screenshot) is always open: the game takes
  -- port_base + 10 or the next free one (Saved/OKControl/<pid>.json). -Control: the driver's behaviour on that exact port.
  if o.control then game[#game + 1] = "-StreetSocialControl" end
  if o.control or sandbox then game[#game + 1] = "-StreetSocialControlPort=" .. control_port end
  -- A sandbox or a controlled run never writes the player's H settings: it starts from a copy and keeps its own.
  local settings_dir = sandbox or (o.control and path.join(root, "Saved/StreetSocial/ControlSettings"))
  if settings_dir then
    path.mkdir(settings_dir, true)
    local shared, own = path.join(os.getenv("LOCALAPPDATA") or "", "OpenKoikatsu/HSettings.ini"), path.join(settings_dir, "HSettings.ini")
    if not path.exists(own) and path.is_file(shared) then path.copy(shared, own) end
    game[#game + 1] = "-OKSettingsDir=" .. settings_dir
  end
  if o.inspect then game[#game + 1] = "-StreetSocialInspect=" .. o.inspect end
  if o.clock then game[#game + 1] = "-StreetSocialClock=" .. o.clock end
  say("StreetSocial: one male + up to ten heroines. WASD move, Shift run, mouse camera, Ctrl/middle UI cursor, wheel zoom, E talk, 1/2/3 topics, Esc cancel, L Chinese/Japanese voices, V built-in/TTS voice, N skip to 07:00 next morning; friendship/confession results save automatically after dialogue; F9 CPU/GPU; conversation buttons: shared walk/explore, photo (P save), seated talk, drinks, splash either direction; Esc ends activity. Reading uses a hand-held book.")
  if o.control then say(("Control channel: http://127.0.0.1:%d (Tools/ok-game-mcp finds it through local-instance.json)"):format(control_port)) end
  local pid = proc.spawn(game, { cwd = root, hide = o.selftest and true or nil })
  print("game pid " .. pid);io.stdout:flush() -- ok-game-mcp watches it: this launcher leaves while the game runs
  path.write_text(path.join(output, "game.pid"), tostring(pid))
  local server_pids = {}
  for _, s in ipairs(servers) do
    local args = { s.file }
    for _, a in ipairs(s.args) do args[#args + 1] = a end
    args[#args + 1] = "--parent-pid"; args[#args + 1] = tostring(pid)
    server_pids[#server_pids + 1] = proc.spawn(args, { cwd = path.parent(s.file), hide = true })
    say(s.name .. " server starting with the game on port " .. s.args[3] .. " (exits when the game closes; model load ~5-10s): " .. s.file)
  end
  -- A normal launch stops this checkout's leftover servers; a running sandbox's are listed here so they are kept.
  if sandbox then path.write_text(path.join(sandbox, "running.json"), json.encode({ game_pid = pid, server_pids = server_pids })) end
  say(output)
end

ok.main(main)
