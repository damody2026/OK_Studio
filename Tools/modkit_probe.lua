-- ModKit probe (OK mod framework work item 3, Docs/OK_MOD_S3_材質可行性.md): runs a mod material pak in the PACKAGED
-- game (no shader compiler, no editor), from Mods/<id>/content/, through ok.ModMaterialProbe (Source/OpenKoikatsu/
-- OKModMaterialProbe.cpp) and keeps the log and a screenshot.
--
--   Tools\lua\lua.exe Tools\modkit_probe.lua stage [--engine DIR]
--       a minimal Development stage under Saved/ModKit/ProbeStage: the game executable already built in Binaries/Win64
--       (Build.bat OpenKoikatsu Win64 Development), a cook of /Engine/Maps/Entry + /Engine/BasicShapes/Plane only (no
--       always-cook directories), UAT staging with legacy paks (-skipiostore, like the StreetSocial stages)
--   Tools\lua\lua.exe Tools\modkit_probe.lua run --mod <id> --pak <file.pak> --tag <name> [--no-library] [--assets a+b]
--       copies the pak to <stage>/OpenKoikatsu/Mods/<id>/content/<id>.pak, starts the game on Entry with
--       GameModeBase, runs the probe, waits for it to quit; evidence under Saved/ModKit/Probe-<tag>/
-- Claim an Unreal slot (Tools/unreal_slot.lua) around both: stage runs the cook commandlet, run starts the game.
local ok = require "ok"
local path, proc = ok.path, ok.proc

local function win(p) return (path.norm(p):gsub("/", "\\")) end
local function step(name) io.write("[", os.date("%H:%M:%S"), "] ", name, "\n"); io.flush() end

local STAGE = "Saved/ModKit/ProbeStage"

local function stage(engine)
  local root = ok.root
  local base = path.join(root, STAGE)
  path.mkdir(base)
  step("cook Entry + Plane")
  local cooked = path.join(base, "Cooked")
  local log = path.join(base, "cook.log")
  local args = { '"' .. win(path.join(root, "OpenKoikatsu.uproject")) .. '"', "-run=Cook", "-TargetPlatform=Windows", "-MAP=/Engine/Maps/Entry",
    "-PACKAGE=/Engine/BasicShapes/Plane", "-NoGameAlwaysCook", "-SkipZenStore", "-CustomConfig=CrowdCookSM6", "-DisablePlugins=BpGeneratorUltimate",
    "-unattended", "-nosound", "-NoSplash", "-corelimit=8", '-OutputDir="' .. win(cooked) .. '\\[Platform]"', '-abslog="' .. win(log) .. '"' }
  local line = '"' .. win(path.join(engine, "Engine/Binaries/Win64/UnrealEditor-Cmd.exe")) .. '" ' .. table.concat(args, " ")
  local r = proc.run(line, { shell = false, hide = true, quiet = true, timeout = 60 * 60 })
  if not r.ok then error("cook failed: " .. win(log), 0) end
  step("stage (legacy pak)")
  local staged = path.join(base, "Stage")
  local uat = proc.run({ win(path.join(engine, "Engine/Build/BatchFiles/RunUAT.bat")), "BuildCookRun",
    "-project=" .. win(path.join(root, "OpenKoikatsu.uproject")), "-nop4", "-nocompile", "-nocompileeditor", "-skipbuild", "-skipcook",
    "-stage", "-pak", "-skipiostore", "-platform=Win64", "-clientconfig=Development", "-CookOutputDir=" .. win(cooked),
    "-stagingdirectory=" .. win(staged), "-MaxParallelActions=8" }, { stdout_file = path.join(base, "stage.log"), merge = true })
  if not uat.ok then error("staging failed: " .. win(path.join(base, "stage.log")), 0) end
  local exe = path.join(staged, "Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe")
  if not path.is_file(exe) then error("no staged executable " .. win(exe), 0) end
  io.write(win(exe), "\n")
end

local function run(a)
  local root = ok.root
  local game = path.join(root, STAGE .. "/Stage/Windows/OpenKoikatsu")
  local exe = path.join(game, "Binaries/Win64/OpenKoikatsu.exe")
  if not path.is_file(exe) then error("no probe stage; run: Tools\\lua\\lua.exe Tools\\modkit_probe.lua stage", 0) end
  if not a.tag:match("^[%w_%-]+$") then error("--tag must match ^[A-Za-z0-9_-]+$", 0) end
  local evidence = path.join(root, "Saved/ModKit/Probe-" .. a.tag)
  if path.exists(evidence) then error("evidence folder exists, use a new --tag: " .. win(evidence), 0) end
  path.mkdir(evidence)
  -- Mods/<id>/content/ next to the game's Content/ (never Content/Paks: the game would mount it by itself).
  local mods = path.join(game, "Mods")
  if path.is_dir(mods) then path.rmtree(mods) end
  local target = path.join(mods, a.mod .. "/content/" .. a.mod .. ".pak")
  path.mkdir(path.parent(target))
  path.copy(path.abs(a.pak), target)
  local shot = path.join(evidence, "probe.png")
  local probe = "ok.ModMaterialProbe Mod=" .. a.mod .. " Shot=" .. win(shot) .. " Quit=1"
  if a.no_library then probe = probe .. " NoLibrary=1" end
  if a.assets ~= "" then probe = probe .. " Assets=" .. a.assets end
  local log = path.join(evidence, "game.log")
  step("game: " .. probe)
  local line = '"' .. win(exe) .. '" /Engine/Maps/Entry?game=/Script/Engine.GameModeBase -windowed -ResX=1280 -ResY=720 -nosound -NoSplash'
    .. ' -ExecCmds="' .. probe .. '" -abslog="' .. win(log) .. '"'
  local r = proc.run(line, { shell = false, quiet = true, timeout = 5 * 60 })
  if r.error == "timeout" then error("game did not quit: " .. win(log), 0) end
  local lines = {}
  for _, l in ipairs(path.read_lines(log)) do if l:find("OKMODPROBE", 1, true) then lines[#lines + 1] = l end end
  path.write_text(path.join(evidence, "probe.txt"), table.concat(lines, "\n") .. "\n")
  for _, l in ipairs(lines) do io.write(l, "\n") end
  io.write(win(log), "\n", path.exists(shot) and win(shot) or "(no screenshot)", "\n")
end

local function main()
  local p = ok.args.parser("ModKit probe: a mod material pak in the packaged game")
  p:arg("command")
  p:opt("--engine", { default = ok.engine_root() })
  p:opt("--mod", { default = "" })
  p:opt("--pak", { default = "" })
  p:opt("--tag", { default = "" })
  p:opt("--assets", { default = "" })
  p:flag("--no-library")
  local a = p:parse(arg)
  if a.command == "stage" then stage(path.norm(a.engine))
  elseif a.command == "run" then
    if a.mod == "" or a.pak == "" or a.tag == "" then error("run needs --mod, --pak and --tag", 0) end
    run(a)
  else error("command: stage | run", 0) end
end

ok.main(main)
