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

-- Running a stage's game from a package (no editor or project): the stage's Content gets links to this folder's
-- IndependentResources, KKPreview and CharacterCards when missing (a copied stage comes without them; the studio's card
-- browser and the reader's StreetHeroines list the game's own Content/CharacterCards), the runtime patch is mounted
-- (runtime.json "patch"), the cooked material parents are named (runtime.json "materials") and the cooked game reads the shared resources by absolute path. Returns the extra arguments
-- and the environment to add.
function M.packaged_launch(root, exe)
  local content = path.join(path.parent(path.parent(path.parent(exe))), "Content")
  for _, name in ipairs({ "IndependentResources", "KKPreview", "CharacterCards" }) do
    local link, target = path.join(content, name), path.join(root, "Content", name)
    if path.is_dir(content) and not path.exists(link) and path.is_dir(target) then
      local made = proc.run({ "cmd", "/c", "mklink", "/J", (link:gsub("/", "\\")), (target:gsub("/", "\\")) }, { quiet = true })
      io.write(made.ok and "Linked " or "Could not link ", link, " -> ", target, "\n")
    end
  end
  local args = {}
  local launch_file = path.join(root, "Content/IndependentResources/StreetSocialData/Launch/runtime.json")
  local launch = path.is_file(launch_file) and json.decode(path.read_text(launch_file)) or {}
  local patch = launch.patch and path.join(root, launch.patch)
  if patch and path.exists(patch) then args[#args + 1] = "-pakdir=" .. patch end
  -- The cooked shared material parents (in the patch): the editor finds them by itself, a packaged game is told
  -- (KKPreviewRuntimeMaterials.inl; not through -StreetSocialManifest=, which turns the reader's UI off).
  local materials_file = launch.materials and path.join(root, launch.materials)
  local materials = materials_file and path.is_file(materials_file) and json.decode(path.read_text(materials_file)) or {}
  if type(materials.root) == "string" and materials.root ~= "" then args[#args + 1] = "-RuntimeMaterialRoot=" .. materials.root end
  if type(materials.hg_root) == "string" and materials.hg_root ~= "" then args[#args + 1] = "-HGMaterialRoot=" .. materials.hg_root end
  return args, { OK_BUILTIN_RESOURCES = (path.join(root, "Content/IndependentResources/v1"):gsub("/", "\\")) }
end

return M
