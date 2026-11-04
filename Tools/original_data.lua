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
--   Tools\lua\lua.exe Tools\original_data.lua manifest-add <group> <path...>   (maintainer: list generated files too)
--
-- restore steps (in order): tools, models, studio, sounds, anims, paired, runtime-clips, preview, archive.
-- Every group says where it comes from (GROUPS need): "game" groups are converted from the original install (--game),
-- "zip" groups only come from the development resources zip (--archive; the features using them are off without it),
-- "no" groups are not needed at all (the street's original lines, voices and translations: she talks through AI free
-- talk and TTS; Studio sample scenes). Docs/SHARED_RESOURCES_SETUP.md is the guide for users and their AI.
-- Regenerated files can differ in bytes from the manifest (converted.tsv timings, sources.okidx lists
-- this machine's mods, re-encoded audio); verify reports them as "differs" and the archive step leaves them alone.
local ok = require "ok"
local path, proc, json, kit = ok.path, ok.proc, ok.json, ok.kit

local ROOT = ok.root
local MANIFEST = ROOT .. "/Tools/original_data_manifest.json"
local LIB = "Content/IndependentResources/base_v1"
local RA = "Content/IndependentResources/RuntimeAnimations"
local SSD = "Content/IndependentResources/StreetSocialData"

-- Paths that are original or zipmod data. A trailing "/" is a folder, "*" matches inside one name. The first group a
-- path matches is its group. need: "game" (converted from the install), "zip" (development resources zip only), "no".
local GROUPS = {
  { name = "base-models", need = "game", step = "models", paths = { LIB .. "/models/" } },
  { name = "base-index", need = "game", step = "models", paths = { LIB .. "/sources.okidx", LIB .. "/converted.tsv", LIB .. "/missing.txt", LIB .. "/oklib.json", LIB .. "/edits.stamp", LIB .. "/shared_mods.txt" } },
  { name = "base-studio", need = "game", step = "studio", paths = { LIB .. "/studio_items.json", LIB .. "/studio_child_animations.json", LIB .. "/shader_states.json", LIB .. "/studio/bg/", LIB .. "/studio/frame/", LIB .. "/studio/sky/", LIB .. "/studio/sky.json", LIB .. "/studio/reflections/", LIB .. "/studio/map_environments.json", LIB .. "/studio/map_reflections.json", LIB .. "/studio/samples/" } },
  { name = "h-voices", need = "game", step = "sounds", paths = { LIB .. "/h/voice/" } },
  { name = "base-sounds", need = "game", step = "sounds", paths = { LIB .. "/studio/voice/", LIB .. "/studio_voices.json", LIB .. "/studio/bgm/", LIB .. "/h/" } },
  { name = "base-anims", need = "game", step = "anims", paths = { LIB .. "/anims/", LIB .. "/studio_anims.json" } },
  { name = "base-paired", need = "game", step = "paired", paths = { LIB .. "/paired/" } },
  { name = "h-poses", need = "game", step = "paired", paths = { SSD .. "/h_poses.json" } },
  { name = "base-other", need = "zip", step = "archive", paths = { LIB .. "/" } },
  { name = "runtime-clips", need = "game", step = "runtime-clips", paths = { RA .. "/" } },
  { name = "preview", need = "game", step = "preview", paths = { "Content/KKPreview/" } },
  { name = "street-voices", need = "no", step = "archive", paths = { SSD .. "/ja_ogg/", SSD .. "/zh_ogg/", SSD .. "/audio_manifest.json", "Content/IndependentResources/RuntimeVoices/" } },
  { name = "street-dialogue", need = "no", step = "archive", paths = { SSD .. "/RuntimeV2/", SSD .. "/RuntimeV3/", SSD .. "/RuntimeV4/", SSD .. "/RuntimeV5/", SSD .. "/RuntimeV5Base/", SSD .. "/TestFixtures/", SSD .. "/catalogue.json", SSD .. "/invitations.json", SSD .. "/gaps.json", SSD .. "/rules.json", SSD .. "/summary.json", SSD .. "/player_context_zh.tsv", SSD .. "/Localization/*/dialogue.json" } },
  { name = "body-motion-data", need = "zip", step = "archive", paths = { "Content/IndependentResources/BodyInteractions/", "Content/IndependentResources/MotionCatalogue/" } },
  { name = "unreal-catalog", need = "zip", step = "archive", paths = { "Content/Koikatsu/Data/", "Content/Scenes/CrowdRoom/SharedWalk/Shared_0000.uasset", "Content/Scenes/CrowdRoom/BehaviorR1Curves/Shared_0000.uasset", "Content/Scenes/CrowdRoom/BehaviorR1Curves/Shared_0001.uasset" } },
  { name = "studio-scenes", need = "no", step = "archive", paths = { "UserData/Studio/scene/", "UserData/Studio/screenshot/", "Docs/images/OKStudio/" } },
}
-- What a "zip" group is used for (the restore report says what is off without it).
local ZIP_USE = {
  ["body-motion-data"] = "one-on-one touch reactions and pair-motion names",
  ["unreal-catalog"] = "the card reader's animation catalogue and the crowd room's shared walk curves",
  ["base-other"] = "other base library files",
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

-- A file the development resources zip carries: everything but the "no" groups (the street's original lines and voices,
-- Studio sample scenes are neither packed nor converted).
local function packed(rel) local g = group_of(rel); return not (g and g.need == "no") end

-- verify(root) -> {same=, differs={}, missing={}} against the manifest (only the packed files with packed_only).
local function verify(root, quiet, packed_only)
  local m = load_manifest()
  if packed_only then
    local files = {}
    for _, f in ipairs(m.files) do if packed(f.path) then files[#files + 1] = f end end
    m.files = files
  end
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
  report.missing_need = {}
  for _, p in ipairs(report.missing) do
    local g = group_of(p); local need = g and g.need or "game"
    report.missing_need[need] = report.missing_need[need] or {}
    local t = report.missing_need[need]; t[g and g.name or "?"] = (t[g and g.name or "?"] or 0) + 1
  end
  return report
end

-- manifest-add <group> <path...>: list generated files (not tracked in git) in the manifest, e.g. the H voices. Each
-- file under the given paths gets its bytes and sha256; existing entries of those paths are replaced.
local function cmd_manifest_add(group, paths)
  assert(group and #paths > 0, "manifest-add <group> <path...>")
  local g
  for _, x in ipairs(GROUPS) do if x.name == group then g = x end end
  assert(g, "unknown group " .. group)
  local m = load_manifest()
  local rels = {}
  for _, rel in ipairs(paths) do
    rel = rel:gsub("\\", "/"):gsub("/+$", "")
    local abs = ROOT .. "/" .. rel
    if path.is_file(abs) then rels[#rels + 1] = rel
    else
      assert(path.is_dir(abs), abs .. ": no such file or folder")
      path.walk(abs, function(dir, _, files)
        for _, name in ipairs(files) do rels[#rels + 1] = (dir .. "/" .. name):sub(#ROOT + 2):gsub("\\", "/") end
      end)
    end
  end
  table.sort(rels)
  for _, rel in ipairs(rels) do assert(group_of(rel) == g, rel .. " is not in group " .. group) end
  local digests = hash_files(ROOT, rels)
  local index = {}
  for i, f in ipairs(m.files) do index[f.path] = i end
  for i, rel in ipairs(rels) do
    local entry = { path = rel, bytes = path.size(ROOT .. "/" .. rel), sha256 = assert(digests[i], rel), group = group }
    if index[rel] then m.files[index[rel]] = entry else m.files[#m.files + 1] = entry end
  end
  table.sort(m.files, function(a, b) return a.path < b.path end)
  ok.write_json(MANIFEST, m, { indent = 1 })
  print(("manifest: %d files of %s listed (%d in all)"):format(#rels, group, #m.files))
end

local function cmd_manifest()
  local tracked = proc.output({ "git", "-C", ROOT, "ls-files", "-z" })
  local rels = {}
  for rel in tracked:gmatch("([^%z]+)") do
    if group_of(rel) then rels[#rels + 1] = rel end
  end
  table.sort(rels)
  -- Since the data left git (2026-11-04) nothing is tracked: rebuilding would empty the manifest.
  assert(#rels > 0, "no tracked original data: the manifest is kept as it is (add generated files with manifest-add)")
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
  local report = verify(ROOT, false, true)
  assert(#report.missing == 0 and #report.differs == 0, "the tree does not match the manifest; pack refuses")
  -- The manifest goes first so a reader finds it cheaply; names are relative to the repository root.
  local names = { "Tools/original_data_manifest.json" }
  for _, f in ipairs(m.files) do if packed(f.path) then names[#names + 1] = f.path end end
  path.mkdir(path.parent(out), true)
  local tmp = out .. ".partial"
  path.remove(tmp, true)
  local r = kit.call({ "zip-create", "-" }, { input = json.encode({ out = tmp, root = ROOT, files = names }) })
  assert(r.files == #names, "zip-create wrote " .. tostring(r.files) .. " members")
  path.remove(out, true)
  path.rename(tmp, out)
  print(("packed %d files -> %s (%.2f GB)"):format(#names - 1, out, path.size(out) / 1e9))
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
  local report = verify(dir, false, true)
  if #report.missing > 0 or #report.differs > 0 then error("archive test failed") end
  print("archive test passed: every file matches its sha256")
end

-- ---------------------------------------------------------------- restore
local function build_tools(target)
  local env = { CARGO_TARGET_DIR = target, RAYON_NUM_THREADS = "8" }
  local manifest = ROOT .. "/Tools/ok-extract/Cargo.toml"
  proc.run({ "cargo", "build", "--release", "-j", "8", "--manifest-path", manifest, "--features", "studio-sounds", "--bin", "ok-extract", "--bin", "ok-paired-library", "--bin", "ok-ramps", "--bin", "ok-hposes" }, { env = env, check = true })
  local bin = target .. "/release/"
  return bin .. "ok-extract.exe", bin .. "ok-paired-library.exe", bin .. "ok-ramps.exe", bin .. "ok-hposes.exe"
end

local function run_logged(log, args)
  print("  > " .. proc.cmdline(args))
  local r = proc.run(args, { stdout_file = log, merge = true, append = true, env = { RAYON_NUM_THREADS = "8" } })
  if not r.ok then error(("failed (%d), see %s"):format(r.code, log)) end
end

local STEPS = { "tools", "models", "studio", "sounds", "anims", "paired", "runtime-clips", "preview", "archive" }

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
  local okx, paired_exe, ramps_exe, hposes_exe = ROOT .. "/Tools/ok-extract/target/release/ok-extract.exe", nil, nil, nil
  local converting = false
  for _, s in ipairs(STEPS) do if s ~= "archive" and want(s) then converting = true end end
  if game and converting then
    print("[tools] building ok-extract (studio-sounds), ok-paired-library, ok-ramps and ok-hposes")
    okx, paired_exe, ramps_exe, hposes_exe = build_tools(work .. "/target")
  end
  local function x(...) run_logged(log, { okx, game, "--oklib", ... }) end
  -- A step that fails (this install lacks something the converter needs) is reported and its files come from the
  -- archive instead, so one missing texture does not leave the rest of the library unrestored.
  local failed = {}
  local function step(name, title, fn)
    if not (game and want(name)) then return end
    print(("[%s] %s"):format(name, title))
    local good, err = pcall(fn)
    if not good then failed[name] = true; print(("[%s] FAILED: %s; its files will come from the archive"):format(name, tostring(err))) end
  end
  step("models", "base library models from the game and its mods/", function() x("convert", lib, "8", "@" .. MODEL_SOURCES) end)
  step("studio", "Studio catalogs, images, sky, reflections, shader states", function()
    x("studio-catalog", lib); x("studio-names", lib); x("studio-nodes", lib, "8"); x("studio-standard-textures", lib)
    x("studio-child-anims", lib); x("studio-images", lib); x("studio-sky", lib); x("studio-environments", lib)
    x("studio-reflections", lib); x("shader-states", lib, "8")
  end)
  step("sounds", "Studio voices, BGM, H sound effects and H voices", function() x("studio-sounds", lib); x("studio-voices", lib); x("h-sounds", lib); x("h-voices", lib) end)
  step("anims", "Studio animations and H motion variants", function() x("anim-convert", lib, "-", "all", "8"); x("anim-pack", lib) end)
  step("paired", "pair motions, poses and IK, the H scene's pose list", function()
    local src = work .. "/PairedAnimations"
    local m = ok.read_json(PAIRED_SOURCES .. "/manifest.json")
    for _, f in ipairs(m.files) do
      local dst = src .. "/" .. f.path
      if path.size(dst) ~= f.bytes then path.mkdir(path.parent(dst), true); path.copy(game .. "/" .. f.path, dst) end
    end
    for _, n in ipairs({ "manifest.json", "editor-demos.json" }) do path.copy(PAIRED_SOURCES .. "/" .. n, src .. "/" .. n) end
    run_logged(log, { paired_exe, "convert", src, lib .. "/paired" })
    -- The H scene's pose list (OKHScene.cpp).
    run_logged(log, { hposes_exe, game, ROOT .. "/" .. SSD .. "/h_poses.json" })
  end)
  step("runtime-clips", "street animation clips", function()
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
  end)
  step("preview", "shadow ramps and the display colour transform (Content/KKPreview)", function()
    local preview = ROOT .. "/Content/KKPreview"
    run_logged(log, { ramps_exe, game, preview .. "/Ramps" })
    -- The KKS display colour transform comes from the BetterColorPicker plugin; without it previews show the plain colours.
    if path.is_file(game .. "/BepInEx/plugins/KKS_BetterColorPicker.dll") then x("saturation-lut", preview)
    else print("  no BepInEx/plugins/KKS_BetterColorPicker.dll: no display colour transform (plain colours)") end
    -- The Minimalist shadow ramp (Docs/CHARACTER_MINIMALIST_NO_SHADOW.md), from its zipmod when the game has it.
    local zipmod
    if path.is_dir(game .. "/mods") then path.walk(game .. "/mods", function(dir, _, files)
      for _, n in ipairs(files) do if not zipmod and n:find("Minimalist Shadows", 1, true) and n:lower():match("%.zip") then zipmod = dir .. "/" .. n end end
    end) end
    if zipmod then
      run_logged(log, { ok.lua_exe, ROOT .. "/Tools/extract_character_ramp.lua", "--zipmod", zipmod, "--bundle", "abdata/chara/Augh/minimalist_shadow.unity3d", "--texture", "minimalist", "--output", preview .. "/MinimalistRamp.png" })
    else print("  no [Augh] Minimalist Shadows zipmod under mods/: no Minimalist ramp") end
  end)
  local report = verify(ROOT, true)
  if want("archive") and o.archive then
    local members, seen = {}, {}
    for _, p in ipairs(report.missing) do if packed(p) then members[#members + 1] = p; seen[p] = true end end
    for _, p in ipairs(report.differs) do
      local g = group_of(p)
      if g and failed[g.step] and not seen[p] then members[#members + 1] = p end
    end
    print(("[archive] %d files from %s"):format(#members, o.archive))
    if #members > 0 then extract(o.archive, ROOT, members) end
  end
  local names = ok.util.sorted_keys(failed)
  if #names > 0 then print("steps that failed on this install (restored from the archive where given): " .. table.concat(names, ", ")) end
  report = verify(ROOT)
  local need = report.missing_need
  if need.no then print("not needed (AI free talk and TTS; Studio sample scenes): " .. table.concat(ok.util.sorted_keys(need.no), ", ")) end
  if need.zip then
    print("only in the development resources zip (QQ group 1127259437; restore --archive <zip>):")
    for _, g in ipairs(ok.util.sorted_keys(need.zip)) do print(("  %s (%d files): %s"):format(g, need.zip[g], ZIP_USE[g] or "")) end
  end
  if need.game then
    print("missing from the game conversion: " .. table.concat(ok.util.sorted_keys(need.game), ", ") .. "; see " .. log)
    return false
  end
  print("restore done: everything converted from the game is in place")
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
  elseif cmd == "manifest-add" then cmd_manifest_add(o[1], { table.unpack(o, 2) })
  elseif cmd == "pack" then cmd_pack(o.out)
  elseif cmd == "verify" then local r = verify(o.root or ROOT); return #r.missing == 0 and #r.differs == 0
  elseif cmd == "test-archive" then cmd_test_archive(o[1], o[2])
  elseif cmd == "restore" then return cmd_restore(o)
  else error("usage: original_data.lua manifest | pack --out <zip> | verify [--root dir] | test-archive <zip> <dir> | restore --game <dir> [--archive <zip>]") end
end

if ok.is_main() then ok.main(main) end
