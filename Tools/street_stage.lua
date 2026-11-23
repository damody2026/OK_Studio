-- StreetSocial stages (Saved/StreetSocial/Build/*.stage): the one place that writes a stage's stage.json and decides
-- which stage is usable and newest. The launcher (run_street_social_development.lua), the scene editor
-- (run_scene_editor.lua) and the packer (package_street_social.lua) all pick through here: when each kept its own copy,
-- the launcher learned to require stage.json while the packer still copied stages without it, and every packaged game
-- refused its only stage and failed to rebuild one (2026-11-15, Docs/ERROR_LOG.md).
--
-- A stage is usable when it has its exe, its Windows/Engine/Binaries (a junction into the base; gone in a half-deleted
-- stage, nh1115z: "tbbmalloc.dll not found") and a stage.json with staged_at. stage.json is written as the stager's last
-- step (stage_street_social.stage), so a stage still being made has none. Newest is by staged_at, not the exe's time:
-- the staged exe is a hard link of the host's, unchanged when a new stage reuses an exe that was not relinked.
-- CrowdRoom*.stage lives in the same folder but is the crowd room's build.
local ok = require "ok"
local json, path, proc = ok.json, ok.path, ok.proc
local lfs = require "lfs"

local M = {}

M.EXE = "Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe"

function M.dir(root) return path.join(root or ok.root, "Saved/StreetSocial/Build") end

-- Writes <stage>/stage.json: when and from what it was made. Call it last, once everything else is in place.
function M.write_meta(stage, executable, base)
  local root = ok.root
  local git = proc.run({ "git", "-C", root, "rev-parse", "HEAD" }, { capture = true, hide = true })
  local dirty = proc.run({ "git", "-C", root, "status", "--porcelain", "--untracked-files=no" }, { capture = true, hide = true })
  local exe = path.abs(executable)
  -- The host project the exe came from (<host>/Binaries/Win64/OpenKoikatsu.exe), else the exe's own folder.
  local host = path.parent(path.parent(path.parent(exe)))
  if path.name(path.parent(exe)):lower() ~= "win64" then host = path.parent(exe) end
  path.write_text(path.join(stage, "stage.json"), json.encode(json.object({
    { "staged_at", os.time() }, { "staged_at_text", os.date("%Y-%m-%d %H:%M:%S") },
    { "commit", ((git.stdout or ""):match("%x+")) or "" }, { "dirty", ((dirty.stdout or ""):match("%S")) ~= nil },
    { "host", host }, { "executable", exe }, { "base", path.abs(base) } }), { indent = 2 }) .. "\n")
end

-- One stage folder (full path): its exe, staged_at, a line saying when and from what, or what makes it unusable.
function M.info(stage)
  local exe = path.join(stage, M.EXE)
  if not path.is_file(exe) then return nil, nil, nil, "no OpenKoikatsu.exe" end
  if not path.is_dir(path.join(stage, "Windows/Engine/Binaries")) then return exe, nil, nil, "Engine/Binaries missing (junction removed)" end
  local meta = path.join(stage, "stage.json")
  if not path.is_file(meta) then return exe, nil, nil, "no stage.json (still being staged, or half deleted)" end
  local okj, m = pcall(json.decode, path.read_text(meta))
  if not okj or type(m) ~= "table" or not tonumber(m.staged_at) then return exe, nil, nil, "stage.json without staged_at" end
  return exe, tonumber(m.staged_at), ("staged_at %s, commit %s%s"):format(m.staged_at_text or "?",
    tostring(m.commit or "?"):sub(1, 9), m.dirty and " +local changes" or "")
end

local function default_say(s) io.write(s, "\n"); io.flush() end

-- Studio*.stage is the OK Studio-only build (rebuild_street_social_runtime.lua --studio: no street or city map cooked),
-- kept apart like CrowdRoom*.stage. kind: nil = a street stage (StreetSocial.cmd), "studio" = Studio stages only (the
-- studio packer), "any" = either (the scene editor runs in both).
function M.is_studio(name) return path.name(name):lower():match("^studio") ~= nil end
function M.kind_ok(name, kind)
  if kind == "any" then return true end
  if kind == "studio" then return M.is_studio(name) end
  return not M.is_studio(name)
end

-- Newest usable StreetSocial stage under root's Saved/StreetSocial/Build. Each stage left out is printed with the reason
-- (through say, default stdout). kind picks street, studio or any stages (M.kind_ok; default street). Returns the exe,
-- the stage folder, its name and its staged_at line; nil when none.
function M.newest(root, say, kind)
  say = say or default_say
  local dir = M.dir(root)
  if not path.is_dir(dir) then return nil end
  local best, best_time, best_name, best_how = nil, -1, nil, nil
  for _, n in ipairs(path.list(dir)) do
    if n:lower():match("%.stage$") and not n:lower():match("^crowdroom") and M.kind_ok(n, kind) then
      local exe, t, how, problem = M.info(path.join(dir, n))
      if problem then say(("  Skipped stage %s: %s"):format(n, problem))
      elseif t > best_time then best, best_time, best_name, best_how = exe, t, n, how end
    end
  end
  if not best then return nil end
  return best, path.join(dir, best_name), best_name, best_how
end

-- A stage by name (with or without .stage, under root's Build folder) or by path: that stage, whatever is newer.
-- One that is missing or not usable is an error. Returns the exe, the stage folder, its name and its staged_at line.
function M.named(root, name, flag)
  flag = flag or "-Stage"
  local stage = path.abs(name):gsub("/+$", "")
  if not path.is_dir(stage) then
    local n = name:lower():match("%.stage$") and name or (name .. ".stage")
    stage = path.join(M.dir(root), n)
    if not path.is_dir(stage) then error(("%s %s: no %s in %s"):format(flag, name, n, M.dir(root)), 0) end
  end
  local exe, _, how, problem = M.info(stage)
  if problem then error(("%s %s: %s"):format(flag, name, problem), 0) end
  return exe, stage, path.name(stage), how
end

-- A path for a -Name=path argument of the game exe. Unreal reads such a value up to the first ',' or ')'
-- (FParse::Value), so a package unpacked as "StreetSocial-20261114-hvoice(1)(1)" mounted no patch and found no
-- manifest: then the path goes relative to the exe's folder (the game's working folder), which leaves the shared prefix
-- with the brackets out. Quotes do not help: the game reads the raw command line, not the MSVC-unquoted argv.
function M.ue_path(exe, p)
  p = path.abs(p)
  if not p:find("[,)%s]") then return p end
  return path.rel(p, path.parent(exe), true)
end

-- Running a stage's game from a package (no editor or project): the stage's Content gets links to this folder's
-- IndependentResources, KKPreview and CharacterCards when missing (a copied stage comes without them; the studio's card
-- browser and the reader's StreetHeroines list the game's own Content/CharacterCards), the runtime patch is mounted
-- (runtime.json "patch"), the cooked material parents are named (runtime.json "materials") and the cooked game reads the shared resources by absolute path. Returns the extra arguments
-- and the environment to add.
-- Links <stage>/Windows/OpenKoikatsu/Content/<name> to root's Content/<name> for each name. A junction left from where
-- the package was unpacked before points at nothing once the folder is moved (E:\Studio-20261117\Studio-20261117 moved
-- up one level, 2026-11-17): the game then found no base library, fell back to Config's game root and every card failed
-- with "game_root missing abdata". Such a junction, or one into another folder, is remade; a real folder is left alone.
function M.link_content(exe, root, names, say)
  say = say or default_say
  local content = path.join(path.parent(path.parent(path.parent(exe))), "Content")
  if not path.is_dir(content) then return end
  local function key(p) return (path.norm(path.abs(p)):gsub("\\", "/"):gsub("/+$", ""):lower()) end
  for _, name in ipairs(names) do
    local link, target = path.join(content, name), path.join(root, "Content", name)
    if path.is_dir(target) then
      -- lfs raises on a junction whose target is gone and returns nil for a missing path.
      local read, attr = pcall(lfs.symlinkattributes, link)
      local stale = not read or (attr and attr.mode == "link" and key(attr.target or "") ~= key(target))
      if stale then
        local gone = proc.run({ "cmd", "/c", "rmdir", (link:gsub("/", "\\")) }, { quiet = true })
        say((gone.ok and "Removed stale link " or "Could not remove stale link ") .. link)
      end
      if stale or (read and not attr) then
        local made = proc.run({ "cmd", "/c", "mklink", "/J", (link:gsub("/", "\\")), (target:gsub("/", "\\")) }, { quiet = true })
        say((made.ok and "Linked " or "Could not link ") .. link .. " -> " .. target)
      end
    end
  end
end

-- The stage's own runtime patch (<X>.stage/Patch, made by rebuild_street_social_runtime.lua from the same editor build
-- as its base) for a stage's game exe, or nil. It goes before Launch/runtime.json's shared patch: that one's
-- RuntimeGlobalShaderPatch-*_P.pak overrides the base's global shader map, so a shared patch made before a new global
-- shader (DreamGUI, the crowd rig) took them away from a freshly cooked base (2026-11-23, F wave 5: the packaged card
-- reader fell back to its old screen).
function M.own_patch(exe)
  local stage = path.abs(exe):gsub("\\", "/"):match("^(.*%.stage)/[Ww]indows/OpenKoikatsu/Binaries/Win64/[^/]+%.exe$")
  if not stage then return nil end
  local patch = path.join(stage, "Patch")
  if path.is_dir(patch) and #path.glob(patch, "*.pak") > 0 then return patch end
  return nil
end

-- The runtime patch to mount for a game exe: the stage's own (M.own_patch), else Launch/runtime.json's.
function M.patch_for(root, exe, launch)
  local own = M.own_patch(exe)
  if own then return own end
  return launch and launch.patch and path.join(root, launch.patch) or nil
end

function M.packaged_launch(root, exe)
  M.link_content(exe, root, { "IndependentResources", "KKPreview", "CharacterCards" })
  local args = {}
  local launch_file = path.join(root, "Content/IndependentResources/StreetSocialData/Launch/runtime.json")
  local launch = path.is_file(launch_file) and json.decode(path.read_text(launch_file)) or {}
  local patch = M.patch_for(root, exe, launch)
  if patch and path.exists(patch) then args[#args + 1] = "-pakdir=" .. M.ue_path(exe, patch) end
  -- The cooked shared material parents (in the patch): the editor finds them by itself, a packaged game is told
  -- (KKPreviewRuntimeMaterials.inl; not through -StreetSocialManifest=, which turns the reader's UI off).
  local materials_file = launch.materials and path.join(root, launch.materials)
  local materials = materials_file and path.is_file(materials_file) and json.decode(path.read_text(materials_file)) or {}
  if type(materials.root) == "string" and materials.root ~= "" then args[#args + 1] = "-RuntimeMaterialRoot=" .. materials.root end
  if type(materials.hg_root) == "string" and materials.hg_root ~= "" then args[#args + 1] = "-HGMaterialRoot=" .. materials.hg_root end
  -- A package (PACKAGE.json, Tools/package_street_social.lua) carries its own base library and no game: the cooked
  -- Config's game root (the build machine's D:/KoikatuSunshine) is not used (KKGameRoot -NoGameRoot).
  if path.is_file(path.join(root, "PACKAGE.json")) then args[#args + 1] = "-NoGameRoot" end
  return args, { OK_BUILTIN_RESOURCES = (path.join(root, "Content/IndependentResources/v1"):gsub("/", "\\")) }
end

return M
