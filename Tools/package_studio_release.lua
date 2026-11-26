-- One command for the OK Studio + card reader + OK mod release package (Docs/OK_STUDIO_MOD_PACKAGE.md): what was done
-- by hand for E:\OKPackage\Studio-20261123-mods-full, step by step, each with its own log.
--
--   Tools\lua\lua.exe Tools\package_studio_release.lua --tag <Name> --cards <OK card folder> --out <new folder>
--     [--zip] [--max-cards 100] [--profile full] [--engine DIR]
--     [--skip-build] [--skip-stage] [--skip-modkit --content-from <folder>]
--   ... --zip-only [--zip-threads 4]   an existing --out: only the self-check, then its zip (no rebuild)
--   ... --program-only [--resources-from <full package>] [--zip]   no --cards: only the program, to lay over an
--                    installation (Docs/PROGRAM_ONLY_UPDATE_PLAN.md); its self-check has it strict-open a full package's
--                    OK cards with that package's resources, and its zip is made after that passed
--
-- Steps (logs in Saved/StudioRelease/<tag>/, one file per step; a failing step names its log and what is missing):
--   1. preflight     engine, cargo, the cards folder, a new --out, nobody measuring (unreal_slot.lua may-build)
--   2. tools         cargo build --release -j 8: ok-extract.exe (the reader's outfit cards and breeding run it from the
--                    package, Tools/ok-extract/target/release/ok-extract.exe, found from the base library's junction by
--                    oklib.rs ok_extract_exe / OKStudioImport.cpp OkExtractExe), ok-game-mcp, the ok-mod workspace
--   3. editor        Build.bat OpenKoikatsuEditor (the cook and the runtime patch use it), -MaxParallelActions=8
--   4. stage         rebuild_street_social_runtime.lua --studio --tag Studio<tag> --base-dir Saved/StreetSocial/BaseStudio<tag>
--                    (game exe, cook of Entry + Template_Default only, pak staging, runtime patch)
--   5. modkit        modkit_cook.lua for every Plugins/org_openkoikatsu_* content plugin: its pak and ui/*.dui
--                    (the pak's content_build is this build's; --skip-modkit takes them from --content-from)
--   6. mods          pack_mod_examples.lua -> .okmod packages; ok-mod-pack profile apply <profile> into the stage's Mods/;
--                    ok-mod-pack verify
--   7. package       package_street_social.lua --studio --private --cards --mods --readme Docs/OK_STUDIO_MOD_PACKAGE.md
--                    (the base library goes in as files; the launchers junction the stage's Content to it on first start)
--   8. self-check    the package: entries, stage exe, tools, mods, panels, paks, maps, the ok-extract.exe search
--
-- --zip-only zips a package made earlier without --zip: preflight (the folder with its PACKAGE.json, no zip yet), the
-- self-check, then <out>.zip of what packaging put there -- the files PACKAGE.json lists, PACKAGE.json and the stage's
-- stage.json -- so what a test run left in the folder since (reader logs, screenshots, settings) stays out, as if --zip
-- had been given; the zip is then read back once (7z t). --zip-threads caps 7-Zip's threads (-mmt) for a machine someone is measuring on.
--
-- All builds use at most 8 threads. Nothing is pushed; the package is private (cards and original data inside).
local ok = require "ok"
local json, path, proc = ok.json, ok.path, ok.proc

local function win(p) return (path.norm(p):gsub("/", "\\")) end
local function say(...) io.write("[", os.date("%H:%M:%S"), "] ", ...); io.write("\n"); io.flush() end
local function fail(msg) error(msg, 0) end

local root = ok.root
local lua = path.join(root, "Tools/lua/lua.exe")
local logs

-- Runs a step's command with its output in <logs>/<name>.log; stops with the log's path when it fails.
local function run(name, args, opts)
  opts = opts or {}
  local log = path.join(logs, name .. ".log")
  local r = proc.run(args, { stdout_file = log, merge = true, cwd = opts.cwd or root, env = opts.env })
  if not r.ok then fail(("%s failed (exit %s): %s"):format(name, tostring(r.code), win(log))) end
  return log
end

local function run_lua(name, script, args, opts)
  local full = { lua, path.join(root, script) }
  for _, v in ipairs(args) do full[#full + 1] = v end
  return run(name, full, opts)
end

-- The last non-empty line of a log (the scripts print their result there).
local function list(dir) return path.is_dir(dir) and path.list(dir) or {} end

local function last_line(log)
  local lines = path.read_lines(log)
  for i = #lines, 1, -1 do if lines[i]:match("%S") then return (lines[i]:gsub("%s+$", "")) end end
  return ""
end

local function wait_may_build()
  local slot = path.join("C:/portable/OpenKoikatsu", "Tools/unreal_slot.lua")
  if not path.is_file(slot) then slot = path.join(root, "Tools/unreal_slot.lua") end
  for i = 1, 120 do
    local r = proc.run({ lua, slot, "may-build" }, { quiet = true })
    if r.ok then return end
    if r.code ~= 3 then fail("unreal_slot.lua may-build failed (exit " .. tostring(r.code) .. ")") end
    if i == 1 then say("someone is measuring (may-build exit 3); waiting") end
    proc.run({ "ping", "-n", "31", "127.0.0.1" }, { quiet = true })
  end
  fail("still not allowed to build after an hour (unreal_slot.lua may-build exit 3)")
end

local CARGO_ENV = { RAYON_NUM_THREADS = "8", CARGO_BUILD_JOBS = "8" }

-- Every tool the package runs, built in step 2, checked in step 8 (in the package, started once). A missing one stops
-- the package here, not in the UI. weights: what the tool needs that the package does not carry, printed at preflight.
local TOOLS = {
  { name = "ok-extract", exe = "Tools/ok-extract/target/release/ok-extract.exe", manifest = "Tools/ok-extract/Cargo.toml",
    build = { "cargo", "build", "--release", "-j", "8", "--bin", "ok-extract" } },
  { name = "ok-game-mcp", exe = "Tools/ok-game-mcp/target/release/ok-game-mcp.exe", manifest = "Tools/ok-game-mcp/Cargo.toml",
    build = { "cargo", "build", "--release", "-j", "8" } },
  { name = "ok-mod-pack", exe = "Tools/ok-mod/target/release/ok-mod-pack.exe", manifest = "Tools/ok-mod/Cargo.toml",
    build = { "cargo", "build", "--release", "-j", "8", "--workspace" } },
  { name = "ok-luakit", exe = "Tools/ok-luakit/target/release/ok-luakit.exe", manifest = "Tools/ok-luakit/Cargo.toml",
    build = { "cargo", "build", "--release", "-j", "8" } },
  { name = "ok-character-mcp", exe = "Tools/character_mcp/bin/ok-character-mcp.exe", build = { "lua", "Tools/character_mcp/build.lua" } },
  -- CPU builds (--no-default-features drops candle's CUDA): the player's machine may have no CUDA.
  { name = "ok-hairdeck", exe = "Tools/ok-hairdeck/target/release/ok-hairdeck.exe", manifest = "Tools/ok-hairdeck/Cargo.toml",
    build = { "cargo", "build", "--release", "-j", "8", "--no-default-features" } },
  { name = "ok-video", exe = "Tools/ok-video/target/release/ok-video.exe", manifest = "Tools/ok-video/Cargo.toml",
    build = { "cargo", "build", "--release", "-j", "8", "--no-default-features" },
    weights = "video import needs the player's own SMPL-X / GVHMR weights (SMPL-X may not be redistributed, GVHMR is "
      .. "non-commercial only): not in the package; Docs/VIDEO_WEIGHTS.md says where they go (or OK_GVHMR_MODELS)" },
}

-- The HairDeck weights ok-hairdeck generate reads (Docs/HAIRDECK.md), copied from --hairdeck-data to the package's
-- HairDeckData/ (ok-hairdeck finds it up from its exe). Not in git. DINOv3 is redistributed under its license, which
-- goes in with it (Licenses/, Tools/package_licenses/THIRD_PARTY.md).
local HAIRDECK_FILES = { "ckpt/image_model", "ckpt/color_model", "ckpt/chain_model", "ckpt/card_vae",
  "data/token_stats_head.json", "data/spring/chain_stats_head.json", "third_party/weights/dinov3/model.safetensors" }
local DINOV3_LICENSE = "third_party/dinov3_src/LICENSE.md"

local function main()
  local p = ok.args.parser("Build, stage and package OK Studio + card reader + OK mods in one run")
  p:opt("--tag", { required = true })
  p:opt("--cards")
  p:opt("--out", { required = true })
  p:flag("--zip")
  -- Only the program (Docs/PROGRAM_ONLY_UPDATE_PLAN.md): laid over an installation that has the resources. Checked
  -- against a full package's resources (--resources-from, default the newest full package beside --out).
  p:flag("--program-only")
  p:opt("--resources-from")
  p:flag("--zip-only")
  p:opt("--zip-threads", { default = "8" })
  p:opt("--max-cards", { default = "100" })
  p:opt("--profile", { default = "full" })
  p:opt("--engine", { default = ok.engine_root() })
  p:flag("--skip-build")
  p:flag("--skip-stage")
  p:flag("--skip-modkit")
  p:opt("--content-from")
  -- 頭髮牌組的素材不在版控裡，放哪是本機的事（OK_HAIRDECK_DATA，預設工作樹底下的 Saved/）。
  p:opt("--hairdeck-data", { default = os.getenv("OK_HAIRDECK_DATA") or (ok.root .. "/Saved/HairDeckData") })

  local a = p:parse(arg)
  if not a.tag:match("^[%w_%-]+$") then fail("--tag must match ^[A-Za-z0-9_-]+$") end
  local tag = a.tag
  local stage_tag = tag:lower():match("^studio") and tag or ("Studio" .. tag)
  local engine = path.norm(a.engine)
  logs = path.join(root, "Saved/StudioRelease/" .. tag)
  path.mkdir(logs)
  local work = logs
  local stage = path.join(root, "Saved/StreetSocial/Build/" .. stage_tag .. ".stage")
  local out = path.abs(a.out):gsub("/+$", "")
  if not a.cards and not a.program_only and not a.zip_only then fail("--cards <OK card folder> is required (a program-only package takes none)") end
  if a.program_only and a.cards then fail("--program-only takes no --cards: cards are resources") end
  local cards = a.cards and path.abs(a.cards)
  local okmod = path.join(root, "Tools/ok-mod")
  local pack_tool = path.join(okmod, "target/release/ok-mod-pack.exe")
  local profile = path.join(okmod, "profiles/" .. a.profile .. ".toml")
  say("logs: ", win(logs))

  if not a.zip_threads:match("^%d+$") or tonumber(a.zip_threads) < 1 then fail("--zip-threads takes a whole number >= 1") end
  local hairdeck = path.abs(a.hairdeck_data)
  local packed
  -- The full package a program-only one is checked against: --resources-from, else the newest folder beside --out whose
  -- PACKAGE.json is a full one (or, made before "kind" was written, that carries a base library).
  local resources_from
  local function find_resources()
    if a.resources_from then return path.abs(a.resources_from):gsub("/+$", "") end
    local best, best_t
    for _, n in ipairs(list(path.parent(out))) do
      local dir = path.join(path.parent(out), n)
      local man = path.join(dir, "PACKAGE.json")
      if dir ~= out and path.is_file(man) and path.is_dir(path.join(dir, "Content/IndependentResources/base_v1")) then
        local okj, m = pcall(json.decode, path.read_text(man))
        if okj and type(m) == "table" and (m.kind == "full" or m.kind == nil) and (not best_t or tostring(m.made) > best_t) then best, best_t = dir, tostring(m.made) end
      end
    end
    return best
  end

  if a.zip_only then
    say("1/8 preflight (--zip-only: the package is there, only the self-check and its zip)")
    local missing = {}
    if not path.is_file(path.join(out, "PACKAGE.json")) then missing[#missing + 1] = "a package made earlier at " .. win(out) .. " (its PACKAGE.json)" end
    if path.exists(out .. ".zip") then missing[#missing + 1] = "no " .. win(out .. ".zip") .. " yet (--zip-only writes it)" end
    if #missing > 0 then fail("missing:\n  - " .. table.concat(missing, "\n  - ")) end
    -- How many packages the run made, for the self-check's count (its packages/ folder is in this tag's logs).
    local made = path.join(work, "packages")
    if path.is_dir(made) then packed = 0; for _, f in ipairs(list(made)) do if f:match("%.okmod$") then packed = packed + 1 end end end
  else

  -- 1. preflight
  say("1/8 preflight")
  local missing = {}
  if not path.is_file(path.join(engine, "Engine/Build/BatchFiles/Build.bat")) then missing[#missing + 1] = "engine Build.bat under " .. win(engine) .. " (--engine)" end
  if not proc.which("cargo") and not path.is_file(path.join(os.getenv("USERPROFILE") or "", ".cargo/bin/cargo.exe")) then missing[#missing + 1] = "cargo (Rust MSVC toolchain)" end
  if not a.program_only and (not path.is_dir(cards) or #path.list(cards) == 0) then missing[#missing + 1] = "OK cards in " .. win(cards) .. " (--cards)" end
  if a.program_only then
    resources_from = find_resources()
    if not resources_from or not path.is_dir(path.join(resources_from, "Content/IndependentResources/base_v1")) then
      missing[#missing + 1] = "a full package to check the program against (--resources-from <folder>; none found beside " .. win(out) .. ")"
    end
  end
  if not path.is_file(profile) then missing[#missing + 1] = "mod profile " .. win(profile) .. " (--profile)" end
  if out:sub(1, #root + 1) == root .. "/" then missing[#missing + 1] = "--out outside the repository (" .. win(out) .. ")" end
  if path.exists(out) and #path.list(out) > 0 then missing[#missing + 1] = "a new or empty --out (" .. win(out) .. " has files)" end
  if a.zip and path.exists(out .. ".zip") then missing[#missing + 1] = "no " .. win(out .. ".zip") .. " yet (--zip writes it)" end
  if a.skip_modkit and not a.content_from then missing[#missing + 1] = "--content-from <folder> with --skip-modkit (<example>/content/*.pak, <example>/ui/*.dui)" end
  if a.skip_stage and not path.is_dir(stage) then missing[#missing + 1] = "the stage " .. win(stage) .. " for --skip-stage" end
  if not a.program_only then
    for _, rel in ipairs(HAIRDECK_FILES) do
      if not path.exists(path.join(hairdeck, rel)) then missing[#missing + 1] = "HairDeck weights " .. win(path.join(hairdeck, rel)) .. " (--hairdeck-data)" end
    end
    if not path.is_file(path.join(hairdeck, DINOV3_LICENSE)) then missing[#missing + 1] = "the DINOv3 license " .. win(path.join(hairdeck, DINOV3_LICENSE)) .. " (it goes in with the weights)" end
  end
  if #missing > 0 then fail("missing:\n  - " .. table.concat(missing, "\n  - ")) end

  -- Features the package cannot offer, said here and not first in the UI.
  for _, t in ipairs(TOOLS) do
    if t.weights then say("  note: ", t.weights) end
  end

  -- 2. tools
  if not a.skip_build then
    say("2/8 tools (-j 8)")
    for _, t in ipairs(TOOLS) do
      -- A running copy (another session's MCP server, a conversion) locks its exe and cargo cannot replace it; a running
      -- exe can still be renamed, so it is moved aside and keeps running from the new name.
      local exe = path.join(root, t.exe)
      if path.is_file(exe) then
        local aside = exe .. ".old-" .. os.date("%Y%m%d%H%M%S")
        if not os.rename(exe, aside) then fail("cannot move " .. win(exe) .. " aside for the build") end
        if not os.remove(aside) then say("  ", t.exe, " is running; the old copy stays as ", path.name(aside)) end
      end
      local cmd = {}
      for _, v in ipairs(t.build) do cmd[#cmd + 1] = v end
      if cmd[1] == "cargo" then
        cmd[#cmd + 1] = "--manifest-path"; cmd[#cmd + 1] = win(path.join(root, t.manifest))
      elseif cmd[1] == "lua" then
        cmd[1] = lua; cmd[2] = path.join(root, cmd[2])
      end
      run("tools-" .. t.name, cmd, { env = CARGO_ENV })
    end
  else say("2/8 tools: skipped (--skip-build)") end
  for _, t in ipairs(TOOLS) do
    if not path.is_file(path.join(root, t.exe)) then fail("not built: " .. t.exe .. " (" .. t.name .. "; run without --skip-build)") end
  end

  -- 3. editor
  if not a.skip_build and not a.skip_stage then
    say("3/8 editor build")
    wait_may_build()
    run("editor", { win(path.join(engine, "Engine/Build/BatchFiles/Build.bat")), "OpenKoikatsuEditor", "Win64", "Development",
      "-Project=" .. win(path.join(root, "OpenKoikatsu.uproject")), "-WaitMutex", "-MaxParallelActions=8" })
  else say("3/8 editor build: skipped") end

  -- 4. stage
  if not a.skip_stage then
    say("4/8 stage ", stage_tag, " (build, cook, pak, patch; logs also in Saved/StreetSocial/Rebuild-", stage_tag, ")")
    wait_may_build()
    run_lua("stage", "Tools/rebuild_street_social_runtime.lua", { "--studio", "--tag", stage_tag, "--engine", win(engine),
      "--base-dir", "Saved/StreetSocial/Base" .. stage_tag })
  else say("4/8 stage: skipped, using ", win(stage)) end
  local stage_exe = path.join(stage, "Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe")
  if not path.is_file(stage_exe) then fail("the stage has no game executable: " .. win(stage_exe)) end

  -- 5. modkit: every content plugin's pak and panels, laid out as <content>/<example>/{content,ui}
  local content_from
  if a.skip_modkit then
    content_from = path.abs(a.content_from)
    say("5/8 modkit: skipped, paks from ", win(content_from))
  else
    say("5/8 modkit")
    content_from = path.join(work, "modcontent")
    if path.is_dir(content_from) then path.rmtree(content_from) end
    for _, dir in ipairs(path.iterdir(path.join(okmod, "examples"))) do
      local manifest = path.join(dir, "mod.toml")
      if path.is_file(manifest) and path.read_text(manifest):match("\ncontent_build%s*=") then
        local example = path.name(dir)
        local plugin = "org_openkoikatsu_" .. example:gsub("%-", "_")
        if not path.is_dir(path.join(root, "Plugins/" .. plugin)) then fail(example .. " has content_build but no Plugins/" .. plugin) end
        say("  ", plugin)
        wait_may_build()
        local cook_out = path.join(work, "modkit/" .. plugin)
        if path.is_dir(cook_out) then path.rmtree(cook_out) end
        local log = run_lua("modkit-" .. example, "Tools/modkit_cook.lua", { "--mod", plugin, "--engine", win(engine), "--out", win(cook_out) })
        local pak = last_line(log)
        if not path.is_file(pak) then fail("modkit_cook.lua printed no pak for " .. plugin .. ": " .. win(log)) end
        local dest = path.join(content_from, example)
        path.mkdir(path.join(dest, "content"))
        path.copy(pak, path.join(dest, "content/" .. path.name(pak)))
        if path.is_dir(path.join(cook_out, "ui")) then path.copytree(path.join(cook_out, "ui"), path.join(dest, "ui")) end
      end
    end
  end

  -- 6. mods: packages, install into the stage, verify
  say("6/8 mods (profile ", a.profile, ")")
  local packages = path.join(work, "packages")
  if path.is_dir(packages) then path.rmtree(packages) end
  local pack_log = run_lua("mods-pack", "Tools/pack_mod_examples.lua", { "--out", win(packages), "--content-from", win(content_from) })
  packed = 0
  for _, f in ipairs(list(packages)) do if f:match("%.okmod$") then packed = packed + 1 end end
  if packed == 0 then fail("no .okmod made: " .. win(pack_log)) end
  local stage_mods = path.join(stage, "Mods")
  run("mods-install", { win(pack_tool), "profile", "apply", win(profile), "--mods", win(stage_mods), "--packages", win(packages) })
  run("mods-verify", { win(pack_tool), "verify", win(stage_mods) })
  say("  ", tostring(packed), " packages; installed into ", win(stage_mods))

  -- 7. package
  say("7/8 package -> ", win(out))
  local pargs = { "--studio", "--private", "--mods", win(packages),
    "--readme", "Docs/OK_STUDIO_MOD_PACKAGE.md", "--stage", win(stage), "--out", win(out) }
  local function extra(src, dest) pargs[#pargs + 1] = "--extra"; pargs[#pargs + 1] = win(src) .. "=" .. dest end
  if a.program_only then
    -- No original data, cards or weights (package_street_social.lua --program-only stops on any); the licenses are the
    -- program's and go in both (the DINOv3 one when this machine has it).
    pargs[#pargs + 1] = "--program-only"
    if path.is_file(path.join(hairdeck, DINOV3_LICENSE)) then extra(path.join(hairdeck, DINOV3_LICENSE), "Licenses/DINOv3-LICENSE.md") end
  else
    for _, v in ipairs({ "--cards", win(cards), "--max-cards", a.max_cards }) do pargs[#pargs + 1] = v end
    for _, rel in ipairs(HAIRDECK_FILES) do extra(path.join(hairdeck, rel), "HairDeckData/" .. rel) end
    extra(path.join(hairdeck, DINOV3_LICENSE), "Licenses/DINOv3-LICENSE.md")
  end
  extra(path.join(root, "Tools/package_licenses/Apache-2.0.txt"), "Licenses/Apache-2.0.txt")
  extra(path.join(root, "Tools/package_licenses/THIRD_PARTY.md"), "Licenses/THIRD_PARTY.md")
  extra(path.join(root, "Docs/VIDEO_WEIGHTS.md"), "Docs/VIDEO_WEIGHTS.md")
  -- No .pdb goes in, the tools' or the game's (user 2026-11-23); the self-check below makes sure.
  -- A program-only zip is made after the self-check passed (it includes the check against the resources), below.
  if a.zip and not a.program_only then pargs[#pargs + 1] = "--zip"; pargs[#pargs + 1] = win(out .. ".zip") end
  run_lua("package", "Tools/package_street_social.lua", pargs)
  end -- not --zip-only

  -- 8. self-check
  say("8/8 self-check")
  local problems = {}
  local function need(rel, what)
    if rel == nil then return end
    if not path.exists(path.join(out, rel)) then problems[#problems + 1] = (what or "missing") .. ": " .. rel end
  end
  local stage_rel = "Saved/StreetSocial/Build/" .. stage_tag .. ".stage"
  local manifest = json.decode(path.read_text(path.join(out, "PACKAGE.json")))
  -- A program-only package (made now, or zipped now with --zip-only): no resources in it, checked against a full one.
  local program = a.program_only or manifest.kind == "program"
  for _, rel in ipairs({ "OKStudio.cmd", "CardReaderDevelopment.cmd", "WriteMcpConfig.cmd", "PACKAGE.json", "OK_STUDIO_MOD_PACKAGE.md",
      stage_rel .. "/Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe", stage_rel .. "/Mods/.installed.toml",
      "Tools/ok-mod/examples", "Docs/OK_MOD_AUTHORING.md" }) do need(rel) end
  if not program then
    for _, rel in ipairs({ "Content/IndependentResources/base_v1/sources.okidx", "Content/IndependentResources/base_v1/anims",
        -- Without this an original card's open has no GUID / override answers and may not walk the mods tree.
        "Content/IndependentResources/base_v1/mods_index.db",
        "Content/IndependentResources/base_v1/studio/voice", "Content/IndependentResources/RuntimeAnimations",
        -- What the resources carry, for a later program to check them against (package_street_social.lua).
        "Content/IndependentResources/RESOURCES.json" }) do need(rel) end
  else
    -- Not one resource file: they would overwrite the installation's own (Docs/PROGRAM_ONLY_UPDATE_PLAN.md).
    local resource = {}
    for _, f in ipairs(json.decode(path.read_text(path.join(root, "Tools/original_data_manifest.json"))).files) do resource[f.path] = true end
    local found = {}
    for _, rel in ipairs(manifest.files or {}) do
      if resource[rel] or rel:sub(1, 23) == "Content/CharacterCards/" or rel:sub(1, 13) == "HairDeckData/" or rel == "Content/IndependentResources/RESOURCES.json" then found[#found + 1] = rel end
    end
    for _, dir in ipairs({ "Content/CharacterCards", "HairDeckData", "Content/IndependentResources/base_v1" }) do
      if path.exists(path.join(out, dir)) then found[#found + 1] = dir .. "/" end
    end
    if #found > 0 then problems[#problems + 1] = ("%d resource path(s) in a program-only package, e.g. %s"):format(#found, found[1]) end
    if manifest.kind ~= "program" then problems[#problems + 1] = "PACKAGE.json kind is " .. tostring(manifest.kind) .. ", not program" end
  end
  -- Every tool: in the package and it starts (any exit code; a missing DLL or a bad image cannot start at all).
  for _, t in ipairs(TOOLS) do
    local exe = path.join(out, t.exe)
    if not path.is_file(exe) then problems[#problems + 1] = "tool missing: " .. t.name .. " (" .. t.exe .. ")"
    else
      local log = path.join(logs, "selfcheck-" .. t.name .. ".log")
      -- Empty stdin: an MCP server (stdio) sees EOF and ends. Windows' loader failures come back as NTSTATUS exit codes.
      local r = proc.run({ win(exe) }, { stdout_file = log, merge = true, input = "", timeout = 30 })
      local loader = { [-1] = "cannot run", [3221225781] = "a DLL is missing (0xC0000135)", [-1073741515] = "a DLL is missing (0xC0000135)",
        [3221225595] = "bad image (0xC000007B)", [-1073741701] = "bad image (0xC000007B)", [3221225785] = "entry point not found (0xC0000139)",
        [-1073741511] = "entry point not found (0xC0000139)" }
      if loader[r.code] then problems[#problems + 1] = ("tool does not start: %s: %s (%s)"):format(t.name, loader[r.code], win(log)) end
    end
  end
  for _, f in ipairs(path.rglob(out, "*.pdb")) do problems[#problems + 1] = "a .pdb is in the package: " .. win(f) end
  -- Launchers must be ASCII only: with the console in UTF-8 (65001) cmd misreads non-ASCII lines and runs pieces of
  -- them ("'H' is not recognized ..." after the card reader started, 2026-11-24).
  for _, f in ipairs(path.rglob(out, "*.cmd")) do
    local fh = io.open(f, "rb")
    local body = fh and fh:read("a") or ""
    if fh then fh:close() end
    if body:find("[\128-\255]") then problems[#problems + 1] = "a launcher has non-ASCII text (cmd misreads it under code page 65001): " .. win(f) end
  end
  for _, rel in ipairs({ "Licenses/THIRD_PARTY.md", "Licenses/Apache-2.0.txt", "Docs/VIDEO_WEIGHTS.md" }) do need(rel) end
  if not program then need("Licenses/DINOv3-LICENSE.md") end
  if not program then for _, rel in ipairs(HAIRDECK_FILES) do need("HairDeckData/" .. rel, "HairDeck weights missing") end end
  -- HairDeck really runs from the package: its own exe, its own weights (HAIRDECK_ROOT cleared, and the weights it
  -- reports must be the package's), one generate on a packaged card (CPU, about 40 s). A program-only package has no
  -- weights (the installation's are used).
  if not program then
    local exe = path.join(out, "Tools/ok-hairdeck/target/release/ok-hairdeck.exe")
    local card
    for _, f in ipairs(path.rglob(path.join(out, "Content/CharacterCards"), "*.png")) do card = f; break end
    local test = path.join(logs, "selfcheck-hairdeck")
    if path.is_dir(test) then path.rmtree(test) end
    local log = path.join(logs, "selfcheck-hairdeck.log")
    if path.is_file(exe) and card then
      say("  HairDeck generate on ", path.name(card), " (CPU)")
      local r = proc.run({ win(exe), "generate", "--image", win(card), "--out", win(test) },
        { stdout_file = log, merge = true, env = { HAIRDECK_ROOT = false, RAYON_NUM_THREADS = "8" }, timeout = 900 })
      local text = path.is_file(log) and path.read_text(log) or ""
      local used = text:match("weights ([^\r\n]+)")
      local inside = used and path.norm(used):lower():sub(1, #out + 1) == (out:lower() .. "/")
      if not r.ok or not path.is_file(path.join(test, "cards_seed0.json")) then
        problems[#problems + 1] = "HairDeck generate failed in the package: " .. win(log)
      elseif not inside then
        problems[#problems + 1] = "HairDeck used weights outside the package (" .. tostring(used) .. "): " .. win(log)
      end
    else problems[#problems + 1] = "HairDeck generate not tried (no exe or no card in the package)" end
  end
  if path.exists(path.join(out, "StreetSocial.cmd")) then problems[#problems + 1] = "StreetSocial.cmd is in a Studio package" end
  -- The ok-extract.exe search (oklib.rs ok_extract_exe): up from the base library and from the game executable.
  local function finds_ok_extract(start)
    local dir = path.norm(start)
    for _ = 0, 9 do
      for _, c in ipairs({ "ok-extract.exe", "Tools/ok-extract/ok-extract.exe", "Tools/ok-extract/target/release/ok-extract.exe" }) do
        if path.is_file(path.join(dir, c)) then return true end
      end
      local up = path.parent(dir)
      if not up or up == dir or up == "." or up == "/" then break end
      dir = up
    end
    return false
  end
  if not program and not finds_ok_extract(path.join(out, "Content/IndependentResources/base_v1")) then problems[#problems + 1] = "ok-extract.exe not found up from the base library" end
  if not finds_ok_extract(path.join(out, stage_rel .. "/Windows/OpenKoikatsu/Binaries/Win64")) then problems[#problems + 1] = "ok-extract.exe not found up from the game executable" end
  -- Mods, packages, panels and paks.
  local pkg_mods = path.join(out, stage_rel .. "/Mods")
  local installed = 0
  for _, n in ipairs(list(pkg_mods)) do
    local d = path.join(pkg_mods, n)
    if path.is_dir(d) and path.is_file(path.join(d, "mod.toml")) then
      installed = installed + 1
      local text = path.read_text(path.join(d, "mod.toml"))
      if text:match("\ncontent_build%s*=") then
        local paks = list(path.join(d, "content"))
        if #paks == 0 then problems[#problems + 1] = path.name(d) .. ": content_build but no content/*.pak" end
      end
      if path.is_dir(path.join(root, "Plugins/org_openkoikatsu_" .. path.name(d):gsub("^org%.openkoikatsu%.", ""):gsub("%-", "_") .. "/DUI")) then
        if not path.is_dir(path.join(d, "ui")) then problems[#problems + 1] = path.name(d) .. ": panels in the plugin but no ui/*.dui" end
      end
    end
  end
  local okmods = 0
  for _, f in ipairs(list(path.join(out, "ModPackages"))) do if f:match("%.okmod$") then okmods = okmods + 1 end end
  if installed == 0 then problems[#problems + 1] = "no mod installed in " .. stage_rel .. "/Mods" end
  if packed and okmods ~= packed then problems[#problems + 1] = ("ModPackages has %d .okmod, %d were made"):format(okmods, packed) end
  local vr = proc.run({ win(path.join(out, "Tools/ok-mod/target/release/ok-mod-pack.exe")), "verify", win(pkg_mods) },
    { stdout_file = path.join(logs, "selfcheck-verify.log"), merge = true })
  if not vr.ok then problems[#problems + 1] = "ok-mod-pack verify failed on the package: " .. win(path.join(logs, "selfcheck-verify.log")) end
  -- Program-only: this program opens the resources it will be laid over. Its own ok-extract strict-opens the OK cards of
  -- a full package with that package's base library (a new process each, no game, no cache: what a player's open needs).
  -- The resource version gate itself is being planned apart (Docs/PROGRAM_ONLY_UPDATE_PLAN.md); this is the working check.
  if program then
    resources_from = resources_from or find_resources()
    local lib = resources_from and path.join(resources_from, "Content/IndependentResources/base_v1")
    local exe = path.join(out, "Tools/ok-extract/target/release/ok-extract.exe")
    if not lib or not path.is_dir(lib) then problems[#problems + 1] = "no full package to check against (--resources-from)"
    else
      local cards_dir = path.join(resources_from, "Content/CharacterCards")
      local tried, failed = 0, {}
      for _, card in ipairs(path.is_dir(cards_dir) and path.rglob(cards_dir, "*.png") or {}) do
        if tried >= 10 then break end
        tried = tried + 1
        local log = path.join(logs, ("selfcheck-resources-%02d.log"):format(tried))
        proc.run({ win(exe), "X:/NoGame", "--oklib", "strict-check", win(lib), win(card) },
          { stdout_file = log, merge = true, env = { OK_NOCACHE = "1", OK_LIBRARY_CACHE = false }, timeout = 300 })
        local text = path.is_file(log) and path.read_text(log) or ""
        if not text:find("OKSTRICT ok") then failed[#failed + 1] = path.name(card) .. " (" .. win(log) .. ")" end
      end
      say(("  against %s: %d OK card(s) strict-opened, %d failed"):format(win(resources_from), tried, #failed))
      -- OK cards never ask the mods index, original cards do: an index this program cannot read answers no GUID, and an
      -- original card opens with every mod "missing" (overlay test 2026-11-24: release-e's schema 1 under a schema 2
      -- program, Illya 42 mods "absent"). Until ok-extract's own resources check is in, the schema this source tree
      -- writes (modsindex.rs SCHEMA) against the one the resources carry.
      local want = path.read_text(path.join(root, "Tools/ok-extract/src/modsindex.rs")):match("const SCHEMA: i64 = (%d+);")
      local db = path.join(lib, "mods_index.db")
      if not path.is_file(db) then problems[#problems + 1] = "the full package has no mods index: " .. win(db)
      else
        local kit = require "ok.kit"
        local okq, rows = pcall(kit.sql_rows, win(db), "SELECT value FROM meta WHERE key='schema'", {}, { readonly = true })
        local have = okq and rows and rows[1] and tostring(rows[1][1]) or "?"
        say(("  mods index of %s: schema %s, this program needs %s"):format(path.name(resources_from), have, tostring(want)))
        if have ~= tostring(want) then
          problems[#problems + 1] = ("the full package's mods index is schema %s, this program needs %s: original cards would find no mod "
            .. "(a full package must go out first, or the player rebuilds it: ok-extract <game> --oklib mods-index <base_v1>)"):format(have, tostring(want))
        end
      end
      if tried == 0 then problems[#problems + 1] = "no OK card in " .. win(cards_dir) .. " to check the program against" end
      if #failed > 0 then
        problems[#problems + 1] = ("this program does not open %d of %d OK card(s) with %s's resources (a full package must go out first): %s")
          :format(#failed, tried, path.name(resources_from), table.concat(failed, "; "))
      end
    end
  end
  -- Breeding, end to end, with the package's own ok-extract and the resources it will run on: two of the cards ->
  -- a child (the reader runs exactly this, `FOkSession::Breed`), the HairDeck hair the step above generated put into
  -- her, and her open checked for a hair part a cooked game can draw. Both of the 2026-11-25 failures fail here: the
  -- child of an original card did not seal at all ("okLt guids"), and the child of two OK cards came out bald in the
  -- package although she was right in the editor (Docs/OK_BREEDING.md).
  do
    local res = program and (resources_from or find_resources()) or out
    local lib = res and path.join(res, "Content/IndependentResources/base_v1")
    local exe = path.join(out, "Tools/ok-extract/target/release/ok-extract.exe")
    local cards_dir = res and path.join(res, "Content/CharacterCards")
    local cards = {}
    for _, f in ipairs(cards_dir and path.is_dir(cards_dir) and path.rglob(cards_dir, "*.png") or {}) do
      local size = path.size(f) or 0
      -- Over 5 MB: an OK card carries her own resources, a plain card or a thumbnail does not.
      if size > 5 * 1024 * 1024 then cards[#cards + 1] = { f, size } end
    end
    table.sort(cards, function(a, b) return a[2] < b[2] end)
    local work = path.join(logs, "selfcheck-breed")
    local env = { OK_BASE_LIBRARY = lib and win(lib) or false, RAYON_NUM_THREADS = "8", OK_NOCACHE = "1" }
    local function step(name, cmd, timeout)
      local log = path.join(logs, "selfcheck-breed-" .. name .. ".log")
      local r = proc.run(cmd, { stdout_file = log, merge = true, env = env, timeout = timeout or 900 })
      return r.ok, path.is_file(log) and path.read_text(log) or "", win(log)
    end
    if not lib or not path.is_dir(lib) or not path.is_file(exe) or #cards < 2 then
      problems[#problems + 1] = "breeding not tried (no base library, no ok-extract, or fewer than two OK cards in " .. win(tostring(cards_dir)) .. ")"
    else
      path.mkdir(work, true)
      -- The parents are cards that have hair themselves: a card whose hairstyle its own data cannot show (crowd_C011
      -- wears hers as an accessory a mod was to provide) is bald on its own account and says nothing about breeding.
      local parents = {}
      for i = 1, math.min(#cards, 10) do
        if #parents == 4 then break end
        local card = cards[i][1]
        local ok, _ = step(("parent-%02d"):format(i), { win(exe), "X:/NoGame", "--oklib", "hair-check", win(card) })
        if ok then parents[#parents + 1] = card end
      end
      if #parents < 2 then problems[#problems + 1] = "breeding not tried (no two cards in " .. win(cards_dir) .. " that open with hair)"
      else
        -- More than one pair: whether a child comes out bald depends on the pair (her hairstyle gene carries only the
        -- game's hair slots, so a parent whose hair is accessories has an empty one -- Docs/OK_BREEDING.md). The
        -- HairDeck hair goes on the first child only; that step is about the hair's material, not about the pair.
        local pairs_to_try = { { 1, 2 } }
        if #parents >= 4 then pairs_to_try[#pairs_to_try + 1] = { 3, 4 }; pairs_to_try[#pairs_to_try + 1] = { 1, 4 }
        elseif #parents == 3 then pairs_to_try[#pairs_to_try + 1] = { 2, 3 } end
        for n, pick in ipairs(pairs_to_try) do
          local mother, father = parents[pick[1]], parents[pick[2]]
          local child = path.join(work, ("child-%d.png"):format(n))
          local haired = path.join(work, ("child-%d-hairdeck.png"):format(n))
          say(("  breeding %s x %s"):format(path.name(mother), path.name(father)))
          local ok1, _, log1 = step(("breed-%d"):format(n), { win(exe), "X:/NoGame", "--oklib", "breed", win(mother), win(father), ("2026112%d"):format(n), win(child) }, 1800)
          if not ok1 or not path.is_file(child) then
            problems[#problems + 1] = "breeding failed in the package: " .. log1
          else
            -- The hair the HairDeck step generated (a full package only), as the reader's breeding puts it on.
            local deck = path.join(logs, "selfcheck-hairdeck/cards_seed0.json")
            local wearer = child
            if n == 1 and path.is_file(deck) then
              local ok2, _, log2 = step("hair-put", { win(exe), "X:/NoGame", "--oklib", "hair-put", win(child), win(deck), win(haired), '{"native":true}' })
              if not ok2 or not path.is_file(haired) then problems[#problems + 1] = "HairDeck hair would not go into the bred child: " .. log2
              else wearer = haired end
            end
            local ok3, text3, log3 = step(("hair-check-%d"):format(n), { win(exe), "X:/NoGame", "--oklib", "hair-check", win(wearer) }, 1800)
            for line in text3:gmatch("OKHAIRCHECK [^\r\n]*") do say("  " .. line) end
            if not ok3 then problems[#problems + 1] = "a bred child has no hair a cooked game would draw: " .. log3 end
          end
        end
      end
    end
  end
  for _, m in ipairs(manifest.maps_in_paks or {}) do
    if not (m:match("Maps/Entry%.umap$") or m:match("Template_Default%.umap$")) then problems[#problems + 1] = "a game map is in the paks: " .. m end
  end
  if #problems > 0 then
    path.write_text(path.join(logs, "selfcheck.txt"), table.concat(problems, "\n") .. "\n")
    fail("self-check failed:\n  - " .. table.concat(problems, "\n  - "))
  end
  path.write_text(path.join(logs, "selfcheck.txt"), "ok\n")
  if a.zip_only or (a.program_only and a.zip) then
    -- What packaging put in the folder: the files PACKAGE.json lists, PACKAGE.json itself and the stage's stage.json
    -- (written after the list). A zip made with --zip at packaging time holds exactly these (checked on
    -- Studio-20261124-release-d: 17609 listed + 2 = the zip's 17611); anything a test run added since stays out.
    local names = {}
    for _, rel in ipairs(manifest.files or {}) do names[#names + 1] = rel end
    names[#names + 1] = "PACKAGE.json"
    names[#names + 1] = stage_rel .. "/stage.json"
    local absent = {}
    for _, rel in ipairs(names) do if not path.is_file(path.join(out, rel)) then absent[#absent + 1] = rel end end
    if #absent > 0 then fail(("%d file(s) PACKAGE.json lists are not in %s, e.g. %s"):format(#absent, win(out), absent[1])) end
    local listfile = path.join(logs, "zip-files.txt")
    local wins = {}
    for i, rel in ipairs(names) do wins[i] = (rel:gsub("/", "\\")) end
    path.write_text(listfile, table.concat(wins, "\n") .. "\n")
    local zip = out .. ".zip"
    local seven = "C:/Program Files/7-Zip/7z.exe"
    if not path.is_file(seven) then fail("--zip-only needs 7-Zip at " .. win(seven)) end
    say(("zip %d files -> %s (7-Zip, %s threads)"):format(#names, win(zip), a.zip_threads))
    -- The same switches package_street_social.lua --zip uses (-tzip -mx=1), the thread count from --zip-threads.
    run("zip", { win(seven), "a", "-tzip", "-mx=1", "-mmt=" .. a.zip_threads, "-scsUTF-8", win(zip), "@" .. win(listfile) }, { cwd = out })
    -- Read back once before it is handed on (a zip of tens of GB nobody tested is not delivered, 2026-11-24).
    say("test ", win(zip), " (7z t)")
    run("zip-test", { win(seven), "t", "-mmt=" .. a.zip_threads, win(zip) })
    say("Zip: ", win(zip), " (", tostring(path.size and path.size(zip) or "?"), " bytes)")
  end
  say(("done: %d mods installed, %d packages, stage %s"):format(installed, okmods, stage_tag))
  io.write(win(out), "\n")
  if a.zip or a.zip_only then io.write(win(out .. ".zip"), "\n") end
end

ok.main(main)
