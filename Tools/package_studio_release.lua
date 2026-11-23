-- One command for the OK Studio + card reader + OK mod release package (Docs/OK_STUDIO_MOD_PACKAGE.md): what was done
-- by hand for E:\OKPackage\Studio-20261123-mods-full, step by step, each with its own log.
--
--   Tools\lua\lua.exe Tools\package_studio_release.lua --tag <Name> --cards <OK card folder> --out <new folder>
--     [--zip] [--max-cards 100] [--profile full] [--engine DIR]
--     [--skip-build] [--skip-stage] [--skip-modkit --content-from <folder>]
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

local function main()
  local p = ok.args.parser("Build, stage and package OK Studio + card reader + OK mods in one run")
  p:opt("--tag", { required = true })
  p:opt("--cards", { required = true })
  p:opt("--out", { required = true })
  p:flag("--zip")
  p:opt("--max-cards", { default = "100" })
  p:opt("--profile", { default = "full" })
  p:opt("--engine", { default = ok.engine_root() })
  p:flag("--skip-build")
  p:flag("--skip-stage")
  p:flag("--skip-modkit")
  p:opt("--content-from")
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
  local cards = path.abs(a.cards)
  local okmod = path.join(root, "Tools/ok-mod")
  local pack_tool = path.join(okmod, "target/release/ok-mod-pack.exe")
  local profile = path.join(okmod, "profiles/" .. a.profile .. ".toml")
  say("logs: ", win(logs))

  -- 1. preflight
  say("1/8 preflight")
  local missing = {}
  if not path.is_file(path.join(engine, "Engine/Build/BatchFiles/Build.bat")) then missing[#missing + 1] = "engine Build.bat under " .. win(engine) .. " (--engine)" end
  if not proc.which("cargo") and not path.is_file(path.join(os.getenv("USERPROFILE") or "", ".cargo/bin/cargo.exe")) then missing[#missing + 1] = "cargo (Rust MSVC toolchain)" end
  if not path.is_dir(cards) or #path.list(cards) == 0 then missing[#missing + 1] = "OK cards in " .. win(cards) .. " (--cards)" end
  if not path.is_file(profile) then missing[#missing + 1] = "mod profile " .. win(profile) .. " (--profile)" end
  if out:sub(1, #root + 1) == root .. "/" then missing[#missing + 1] = "--out outside the repository (" .. win(out) .. ")" end
  if path.exists(out) and #path.list(out) > 0 then missing[#missing + 1] = "a new or empty --out (" .. win(out) .. " has files)" end
  if a.zip and path.exists(out .. ".zip") then missing[#missing + 1] = "no " .. win(out .. ".zip") .. " yet (--zip writes it)" end
  if a.skip_modkit and not a.content_from then missing[#missing + 1] = "--content-from <folder> with --skip-modkit (<example>/content/*.pak, <example>/ui/*.dui)" end
  if a.skip_stage and not path.is_dir(stage) then missing[#missing + 1] = "the stage " .. win(stage) .. " for --skip-stage" end
  if #missing > 0 then fail("missing:\n  - " .. table.concat(missing, "\n  - ")) end

  -- 2. tools
  if not a.skip_build then
    say("2/8 tools (cargo -j 8)")
    -- A running copy (another session's MCP server, a conversion) locks its exe and cargo cannot replace it; a running
    -- exe can still be renamed, so it is moved aside and keeps running from the new name.
    for _, rel in ipairs({ "Tools/ok-extract/target/release/ok-extract.exe", "Tools/ok-game-mcp/target/release/ok-game-mcp.exe",
        "Tools/ok-mod/target/release/ok-mod-pack.exe" }) do
      local exe = path.join(root, rel)
      if path.is_file(exe) then
        local aside = exe .. ".old-" .. os.date("%Y%m%d%H%M%S")
        if not os.rename(exe, aside) then fail("cannot move " .. win(exe) .. " aside for the build") end
        if not os.remove(aside) then say("  ", rel, " is running; the old copy stays as ", path.name(aside)) end
      end
    end
    run("tools-ok-extract", { "cargo", "build", "--release", "-j", "8", "--bin", "ok-extract", "--manifest-path", win(path.join(root, "Tools/ok-extract/Cargo.toml")) }, { env = CARGO_ENV })
    run("tools-ok-game-mcp", { "cargo", "build", "--release", "-j", "8", "--manifest-path", win(path.join(root, "Tools/ok-game-mcp/Cargo.toml")) }, { env = CARGO_ENV })
    run("tools-ok-mod", { "cargo", "build", "--release", "-j", "8", "--workspace", "--manifest-path", win(path.join(okmod, "Cargo.toml")) }, { env = CARGO_ENV })
  else say("2/8 tools: skipped (--skip-build)") end
  for _, rel in ipairs({ "Tools/ok-extract/target/release/ok-extract.exe", "Tools/ok-game-mcp/target/release/ok-game-mcp.exe",
      "Tools/ok-mod/target/release/ok-mod-pack.exe" }) do
    if not path.is_file(path.join(root, rel)) then fail("not built: " .. rel .. " (run without --skip-build)") end
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
  local packed = 0
  for _, f in ipairs(list(packages)) do if f:match("%.okmod$") then packed = packed + 1 end end
  if packed == 0 then fail("no .okmod made: " .. win(pack_log)) end
  local stage_mods = path.join(stage, "Mods")
  run("mods-install", { win(pack_tool), "profile", "apply", win(profile), "--mods", win(stage_mods), "--packages", win(packages) })
  run("mods-verify", { win(pack_tool), "verify", win(stage_mods) })
  say("  ", tostring(packed), " packages; installed into ", win(stage_mods))

  -- 7. package
  say("7/8 package -> ", win(out))
  local pargs = { "--studio", "--private", "--cards", win(cards), "--max-cards", a.max_cards, "--mods", win(packages),
    "--readme", "Docs/OK_STUDIO_MOD_PACKAGE.md", "--stage", win(stage), "--out", win(out) }
  if a.zip then pargs[#pargs + 1] = "--zip"; pargs[#pargs + 1] = win(out .. ".zip") end
  run_lua("package", "Tools/package_street_social.lua", pargs)

  -- 8. self-check
  say("8/8 self-check")
  local problems = {}
  local function need(rel, what)
    if not path.exists(path.join(out, rel)) then problems[#problems + 1] = (what or "missing") .. ": " .. rel end
  end
  local stage_rel = "Saved/StreetSocial/Build/" .. stage_tag .. ".stage"
  for _, rel in ipairs({ "OKStudio.cmd", "CardReaderDevelopment.cmd", "WriteMcpConfig.cmd", "PACKAGE.json", "OK_STUDIO_MOD_PACKAGE.md",
      stage_rel .. "/Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe", stage_rel .. "/Mods/.installed.toml",
      "Tools/ok-extract/target/release/ok-extract.exe", "Tools/ok-mod/target/release/ok-mod-pack.exe",
      "Tools/ok-game-mcp/target/release/ok-game-mcp.exe", "Tools/ok-mod/examples", "Docs/OK_MOD_AUTHORING.md",
      "Content/IndependentResources/base_v1/sources.okidx", "Content/IndependentResources/base_v1/anims",
      "Content/IndependentResources/base_v1/studio/voice", "Content/IndependentResources/RuntimeAnimations" }) do need(rel) end
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
  if not finds_ok_extract(path.join(out, "Content/IndependentResources/base_v1")) then problems[#problems + 1] = "ok-extract.exe not found up from the base library" end
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
  if okmods ~= packed then problems[#problems + 1] = ("ModPackages has %d .okmod, %d were made"):format(okmods, packed) end
  local vr = proc.run({ win(path.join(out, "Tools/ok-mod/target/release/ok-mod-pack.exe")), "verify", win(pkg_mods) },
    { stdout_file = path.join(logs, "selfcheck-verify.log"), merge = true })
  if not vr.ok then problems[#problems + 1] = "ok-mod-pack verify failed on the package: " .. win(path.join(logs, "selfcheck-verify.log")) end
  local manifest = json.decode(path.read_text(path.join(out, "PACKAGE.json")))
  for _, m in ipairs(manifest.maps_in_paks or {}) do
    if not (m:match("Maps/Entry%.umap$") or m:match("Template_Default%.umap$")) then problems[#problems + 1] = "a game map is in the paks: " .. m end
  end
  if #problems > 0 then
    path.write_text(path.join(logs, "selfcheck.txt"), table.concat(problems, "\n") .. "\n")
    fail("self-check failed:\n  - " .. table.concat(problems, "\n  - "))
  end
  path.write_text(path.join(logs, "selfcheck.txt"), "ok\n")
  say(("done: %d mods installed, %d packages, stage %s"):format(installed, okmods, stage_tag))
  io.write(win(out), "\n")
  if a.zip then io.write(win(out .. ".zip"), "\n") end
end

ok.main(main)
