-- Original game data kept out of git (Docs/ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md).
--
-- Everything converted from the original Koikatsu Sunshine install (abdata, UserData, voices) or from
-- third-party zipmods is not versioned. Tools/original_data_manifest.json lists every such file (path,
-- bytes, sha256, group); this script packs them into a zip, checks a tree against the manifest and
-- restores them, regenerating from the game where a converter exists and taking the rest from the zip.
--
--   Tools\lua\lua.exe Tools\original_data.lua restore --game D:/KoikatuSunshine [--archive F:/backup/OKOriginalData.zip] [--only <step,...>] [--skip <step,...>]
--   Tools\lua\lua.exe Tools\original_data.lua verify [--root <dir>]
--   Tools\lua\lua.exe Tools\original_data.lua pack --out F:/backup/OKOriginalData.zip
--   Tools\lua\lua.exe Tools\original_data.lua test-archive <zip> <empty dir>
--   Tools\lua\lua.exe Tools\original_data.lua manifest            (maintainer: rebuild the manifest from tracked files)
--
-- restore steps (in order): tools, models, studio, sounds, anims, paired, runtime-clips, archive.
-- With only --game every file a converter produces comes back; the rest (street voices and dialogue,
-- translations, KKPreview ramps, catalog DataTables, crowd curves, Studio scenes) needs --archive.
-- Regenerated files can differ in bytes from the manifest (converted.tsv timings, sources.okidx lists
-- this machine's mods); verify reports them as "differs" and the archive step leaves them alone.
local ok = require "ok"
local path, proc, json, kit = ok.path, ok.proc, ok.json, ok.kit

local ROOT = ok.root
local MANIFEST = ROOT .. "/Tools/original_data_manifest.json"
local LIB = "Content/IndependentResources/base_v1"
local RA = "Content/IndependentResources/RuntimeAnimations"
local SSD = "Content/IndependentResources/StreetSocialData"

-- Tracked paths that are original or zipmod data. A trailing "/" is a folder, "*" matches inside one name.
local GROUPS = {
  { name = "base-models", step = "models", paths = { LIB .. "/models/" } },
  { name = "base-index", step = "models", paths = { LIB .. "/sources.okidx", LIB .. "/converted.tsv", LIB .. "/missing.txt", LIB .. "/oklib.json", LIB .. "/edits.stamp", LIB .. "/shared_mods.txt" } },
  { name = "base-studio", step = "studio", paths = { LIB .. "/studio_items.json", LIB .. "/studio_child_animations.json", LIB .. "/shader_states.json", LIB .. "/studio/bg/", LIB .. "/studio/frame/", LIB .. "/studio/sky/", LIB .. "/studio/sky.json", LIB .. "/studio/reflections/", LIB .. "/studio/map_environments.json", LIB .. "/studio/map_reflections.json", LIB .. "/studio/samples/" } },
  { name = "base-sounds", step = "sounds", paths = { LIB .. "/studio/voice/", LIB .. "/studio_voices.json", LIB .. "/studio/bgm/", LIB .. "/h/" } },
  { name = "base-anims", step = "anims", paths = { LIB .. "/anims/", LIB .. "/studio_anims.json" } },
  { name = "base-paired", step = "paired", paths = { LIB .. "/paired/" } },
  { name = "base-other", step = "archive", paths = { LIB .. "/" } },
  { name = "runtime-clips", step = "runtime-clips", paths = { RA .. "/" } },
  { name = "street-voices", step = "archive", paths = { SSD .. "/ja_ogg/", SSD .. "/zh_ogg/", SSD .. "/audio_manifest.json", "Content/IndependentResources/RuntimeVoices/" } },
  { name = "street-dialogue", step = "archive", paths = { SSD .. "/RuntimeV2/", SSD .. "/RuntimeV3/", SSD .. "/RuntimeV4/", SSD .. "/RuntimeV5/", SSD .. "/RuntimeV5Base/", SSD .. "/TestFixtures/", SSD .. "/catalogue.json", SSD .. "/invitations.json", SSD .. "/gaps.json", SSD .. "/rules.json", SSD .. "/summary.json", SSD .. "/h_poses.json", SSD .. "/player_context_zh.tsv", SSD .. "/Localization/*/dialogue.json" } },
  { name = "body-motion-data", step = "archive", paths = { "Content/IndependentResources/BodyInteractions/", "Content/IndependentResources/MotionCatalogue/" } },
  { name = "unreal-catalog", step = "archive", paths = { "Content/Koikatsu/Data/", "Content/KKPreview/", "Content/Scenes/CrowdRoom/SharedWalk/Shared_0000.uasset", "Content/Scenes/CrowdRoom/BehaviorR1Curves/Shared_0000.uasset", "Content/Scenes/CrowdRoom/BehaviorR1Curves/Shared_0001.uasset" } },
  { name = "studio-scenes", step = "archive", paths = { "UserData/Studio/scene/", "UserData/Studio/screenshot/", "Docs/images/OKStudio/" } },
}

-- Name lists the converters read; versioned, they hold only source paths and keys.
local MODEL_SOURCES = ROOT .. "/Tools/original_data/model_sources.txt"
local PAIRED_SOURCES = ROOT .. "/Tools/original_data/paired"
local CLIP_SOURCES = ROOT .. "/Tools/original_data/runtime_clips.tsv"

local function group_of(rel)
  for _, g in ipairs(GROUPS) do
    for _, p in ipairs(g.paths) do
      if p:sub(-1) == "/" then
        if rel:sub(1, #p) == p then return g end
      elseif p:find("*", 1, true) then
        local pat = "^" .. p:gsub("[%.%-%+%?%^%$%(%)%[%]%%]", "%%%0"):gsub("%*", "[^/]+") .. "$"
        if rel:match(pat) then return g end
      elseif rel == p then return g end
    end
  end
end

local function hash_files(root, rels)
  local abs = {}
  for i, r in ipairs(rels) do abs[i] = root .. "/" .. r end
  local out = {}
  for i = 1, #abs, 2000 do
    local part = { table.unpack(abs, i, math.min(i + 1999, #abs)) }
    local digests = kit.call({ "hash-many", "sha256", "-" }, { input = table.concat(part, "\n") .. "\n" })
    for j, d in ipairs(digests) do out[i + j - 1] = d ~= json.null and d or nil end
  end
  return out
end

local function load_manifest() return ok.read_json(MANIFEST) end

-- verify(root) -> {same=, differs={}, missing={}} against the manifest.
local function verify(root, quiet)
  local m = load_manifest()
  local rels, present = {}, {}
  for _, f in ipairs(m.files) do
    if path.is_file(root .. "/" .. f.path) then rels[#rels + 1] = f.path end
  end
  local digests = hash_files(root, rels)
  for i, r in ipairs(rels) do present[r] = digests[i] end
  local report = { same = 0, differs = {}, missing = {} }
  for _, f in ipairs(m.files) do
    local d = present[f.path]
    if not d then report.missing[#report.missing + 1] = f.path
    elseif d ~= f.sha256 then report.differs[#report.differs + 1] = f.path
    else report.same = report.same + 1 end
  end
  if not quiet then
    print(("verify %s: %d same, %d differ, %d missing (of %d)"):format(root, report.same, #report.differs, #report.missing, #m.files))
    local by = {}
    for _, kind in ipairs({ "differs", "missing" }) do
      for _, p in ipairs(report[kind]) do
        local g = group_of(p); local k = kind .. " " .. (g and g.name or "?")
        by[k] = (by[k] or 0) + 1
      end
    end
    for _, k in ipairs(ok.util.sorted_keys(by)) do print(("  %-28s %d"):format(k, by[k])) end
  end
  return report
end

local function cmd_manifest()
  local tracked = proc.output({ "git", "-C", ROOT, "ls-files", "-z" })
  local rels = {}
  for rel in tracked:gmatch("([^%z]+)") do
    if group_of(rel) then rels[#rels + 1] = rel end
  end
  table.sort(rels)
  local status = proc.output({ "git", "-C", ROOT, "status", "--porcelain", "--", table.unpack({ LIB, RA, SSD }) })
  if status:find("%S") then print("warning: working tree differs from HEAD under the listed folders:\n" .. status) end
  local digests = hash_files(ROOT, rels)
  local files, bytes = {}, 0
  for i, rel in ipairs(rels) do
    local size = path.size(ROOT .. "/" .. rel)
    assert(digests[i], rel .. ": cannot read")
    files[i] = { path = rel, bytes = size, sha256 = digests[i], group = group_of(rel).name }
    bytes = bytes + size
  end
  ok.write_json(MANIFEST, { schema = 1, purpose = "Original game and zipmod data kept out of git; Tools/original_data.lua", files = files }, { indent = 1 })
  print(("manifest: %d files, %.2f GB -> %s"):format(#files, bytes / 1e9, MANIFEST))
  -- The converters' name lists, from the tracked library.
  local tracked_models = {}
  for _, f in ipairs(files) do
    local id = f.path:match("^" .. LIB:gsub("%-", "%%-") .. "/models/%x%x/(%x+)%.okmodel$")
    if id then tracked_models[id] = true end
  end
  local labels, seen = {}, {}
  for line in io.lines(ROOT .. "/" .. LIB .. "/converted.tsv") do
    local label, state, _, id = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)\t(%x+)")
    if label and state == "ok" and tracked_models[id] and not seen[label] then seen[label] = true; labels[#labels + 1] = label end
  end
  table.sort(labels)
  path.mkdir(ROOT .. "/Tools/original_data", true)
  path.write_text(MODEL_SOURCES, table.concat(labels, "\n") .. "\n")
  print(("model sources: %d labels for %d tracked models"):format(#labels, ok.util.len(tracked_models)))
  path.mkdir(PAIRED_SOURCES, true)
  for _, n in ipairs({ "manifest.json", "editor-demos.json" }) do path.copy(ROOT .. "/" .. LIB .. "/paired/" .. n, PAIRED_SOURCES .. "/" .. n) end
  local clips = {}
  for _, mf in ipairs(path.glob(ROOT .. "/" .. RA, "*.manifest.json")) do
    local function walk(v)
      if type(v) ~= "table" then return end
      if type(v.source) == "string" and type(v.file) == "string" and v.source:find("|", 1, true) and not v.file:find("/", 1, true) then
        clips[v.file] = v.source
      end
      for _, x in pairs(v) do walk(x) end
    end
    if path.name(mf) ~= "library.manifest.json" then walk(ok.read_json(mf)) end
  end
  local rows = {}
  for _, file in ipairs(ok.util.sorted_keys(clips)) do rows[#rows + 1] = file .. "\t" .. clips[file] end
  path.write_text(CLIP_SOURCES, table.concat(rows, "\n") .. "\n")
  print(("runtime clips: %d with a source key"):format(#rows))
end

local function cmd_pack(out)
  assert(out, "pack --out <zip>")
  local m = load_manifest()
  local report = verify(ROOT)
  assert(#report.missing == 0 and #report.differs == 0, "the tree does not match the manifest; pack refuses")
  -- The manifest goes first so a reader finds it cheaply; names are relative to the repository root.
  local names = { "Tools/original_data_manifest.json" }
  for _, f in ipairs(m.files) do names[#names + 1] = f.path end
  path.mkdir(path.parent(out), true)
  local tmp = out .. ".partial"
  path.remove(tmp, true)
  local r = kit.call({ "zip-create", "-" }, { input = json.encode({ out = tmp, root = ROOT, files = names }) })
  assert(r.files == #names, "zip-create wrote " .. tostring(r.files) .. " members")
  path.remove(out, true)
  path.rename(tmp, out)
  print(("packed %d files -> %s (%.2f GB)"):format(#m.files, out, path.size(out) / 1e9))
end

-- Extract the named members (all when nil) of the archive into root.
local function extract(archive, root, members)
  path.mkdir(root, true)
  local args = { "zip-extract", archive, root }
  local input
  if members then args[#args + 1] = "-"; input = table.concat(members, "\n") end
  local r = kit.call(args, { input = input })
  print(("extracted %d files from %s"):format(r.files, archive))
end

local function cmd_test_archive(archive, dir)
  assert(archive and dir, "test-archive <zip> <empty dir>")
  assert(not path.exists(dir) or #path.list(dir) == 0, dir .. " is not empty")
  extract(archive, dir)
  local inner = ok.read_json(dir .. "/Tools/original_data_manifest.json")
  local outer = load_manifest()
  assert(#inner.files == #outer.files, "archive manifest differs from Tools/original_data_manifest.json")
  local report = verify(dir)
  if #report.missing > 0 or #report.differs > 0 then error("archive test failed") end
  print("archive test passed: every file matches its sha256")
end

-- ---------------------------------------------------------------- restore
local function build_tools(target)
  local env = { CARGO_TARGET_DIR = target, RAYON_NUM_THREADS = "8" }
  local manifest = ROOT .. "/Tools/ok-extract/Cargo.toml"
  proc.run({ "cargo", "build", "--release", "-j", "8", "--manifest-path", manifest, "--features", "studio-sounds", "--bin", "ok-extract", "--bin", "ok-paired-library" }, { env = env, check = true })
  return target .. "/release/ok-extract.exe", target .. "/release/ok-paired-library.exe"
end

local function run_logged(log, args)
  print("  > " .. proc.cmdline(args))
  local r = proc.run(args, { stdout_file = log, merge = true, append = true, env = { RAYON_NUM_THREADS = "8" } })
  if not r.ok then error(("failed (%d), see %s"):format(r.code, log)) end
end

local STEPS = { "tools", "models", "studio", "sounds", "anims", "paired", "runtime-clips", "archive" }

local function cmd_restore(o)
  local game = o.game and o.game:gsub("\\", "/"):gsub("/+$", "")
  local only, skip = ok.util.set(o.only), ok.util.set(o.skip)
  local function want(s) return (not o.only or only[s]) and not skip[s] end
  if not game then
    for _, s in ipairs(STEPS) do if s ~= "archive" then skip[s] = true end end
    assert(o.archive, "give --game <original install>, --archive <zip>, or both")
  else
    assert(path.is_dir(game .. "/abdata"), game .. ": no abdata folder")
  end
  local work = ROOT .. "/Saved/OriginalData"
  path.mkdir(work, true)
  local log = work .. "/restore.log"
  local lib = ROOT .. "/" .. LIB
  path.mkdir(lib, true)
  local okx, paired_exe = ROOT .. "/Tools/ok-extract/target/release/ok-extract.exe", nil
  if game and (want("tools") or want("models") or want("studio") or want("sounds") or want("anims") or want("paired") or want("runtime-clips")) then
    print("[tools] building ok-extract (studio-sounds) and ok-paired-library")
    okx, paired_exe = build_tools(work .. "/target")
  end
  local function x(...) run_logged(log, { okx, game, "--oklib", ... }) end
  if game and want("models") then
    print("[models] base library models from the game and its mods/")
    x("convert", lib, "8", "@" .. MODEL_SOURCES)
  end
  if game and want("studio") then
    print("[studio] Studio catalogs, images, sky, reflections, shader states")
    x("studio-catalog", lib); x("studio-names", lib); x("studio-nodes", lib, "8"); x("studio-standard-textures", lib)
    x("studio-child-anims", lib); x("studio-images", lib); x("studio-sky", lib); x("studio-environments", lib)
    x("studio-reflections", lib); x("shader-states", lib, "8")
  end
  if game and want("sounds") then
    print("[sounds] Studio voices, BGM, H sound effects")
    x("studio-sounds", lib); x("studio-voices", lib); x("h-sounds", lib)
  end
  if game and want("anims") then
    print("[anims] Studio animations and H motion variants")
    x("anim-convert", lib, "-", "all", "8"); x("anim-pack", lib)
  end
  if game and want("paired") then
    print("[paired] pair motions, poses and IK")
    local src = work .. "/PairedAnimations"
    local m = ok.read_json(PAIRED_SOURCES .. "/manifest.json")
    for _, f in ipairs(m.files) do
      local dst = src .. "/" .. f.path
      if path.size(dst) ~= f.bytes then path.mkdir(path.parent(dst), true); path.copy(game .. "/" .. f.path, dst) end
    end
    for _, n in ipairs({ "manifest.json", "editor-demos.json" }) do path.copy(PAIRED_SOURCES .. "/" .. n, src .. "/" .. n) end
    run_logged(log, { paired_exe, "convert", src, lib .. "/paired" })
  end
  if game and want("runtime-clips") then
    print("[runtime-clips] street animation clips")
    path.mkdir(ROOT .. "/" .. RA .. "/library", true)
    local rows = {}
    for line in io.lines(CLIP_SOURCES) do
      local file, key = line:match("^([^\t]+)\t(.+)$")
      if file then rows[#rows + 1] = ROOT .. "/" .. RA .. "/" .. file .. "\t" .. key end
    end
    local tsv = work .. "/runtime_clips.tsv"
    path.write_text(tsv, table.concat(rows, "\n") .. "\n")
    run_logged(log, { okx, game, "--export-runtime-clips", tsv })
    run_logged(log, { ok.lua_exe, ROOT .. "/Tools/export_street_animation_library.lua", "--game", game, "--exe", okx })
  end
  local report = verify(ROOT, true)
  if want("archive") and o.archive then
    print(("[archive] %d missing files from %s"):format(#report.missing, o.archive))
    if #report.missing > 0 then extract(o.archive, ROOT, report.missing) end
  end
  report = verify(ROOT)
  if #report.missing > 0 then
    print("still missing; " .. (o.archive and "the archive does not have them" or "give --archive <zip> for the files no converter makes"))
    return false
  end
  return true
end

local function main()
  local cmd = arg[1]
  local o, i = {}, 2
  while arg[i] do
    local a = arg[i]
    if a == "--game" or a == "--archive" or a == "--out" or a == "--root" then o[a:sub(3)] = arg[i + 1]; i = i + 2
    elseif a == "--only" or a == "--skip" then o[a:sub(3)] = ok.util.split(arg[i + 1], ","); i = i + 2
    else o[#o + 1] = a; i = i + 1 end
  end
  if cmd == "manifest" then cmd_manifest()
  elseif cmd == "pack" then cmd_pack(o.out)
  elseif cmd == "verify" then local r = verify(o.root or ROOT); return #r.missing == 0 and #r.differs == 0
  elseif cmd == "test-archive" then cmd_test_archive(o[1], o[2])
  elseif cmd == "restore" then return cmd_restore(o)
  else error("usage: original_data.lua manifest | pack --out <zip> | verify [--root dir] | test-archive <zip> <dir> | restore --game <dir> [--archive <zip>]") end
end

if ok.is_main() then ok.main(main) end
