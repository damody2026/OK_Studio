-- Packs the street (StreetSocial) into a folder (and optionally a zip) another player can run: the staged game, the
-- runtime patch, the launcher and its Lua tools, the voice servers, the versioned Content, and a new player's settings
-- file with no keys (Saved/StreetSocial/player.json, Tools/street_player_settings.lua). Docs/STREET_SOCIAL_PACKAGE.md.
--
--   Tools\lua\lua.exe Tools\package_street_social.lua --out <folder> [--stage <Saved/StreetSocial/Build/X.stage>]
--     [--zip <file.zip>] [--check] [--allow <Content/prefix>]... [--no-voice-servers]
--
-- Nothing copyrighted goes in (AGENTS.md): no original game or zipmod data (Tools/original_data_manifest.json), no
-- character cards, no saves, no keys. Of the project's Content only the files tracked in git are taken; the player
-- restores the original data from their own game (Tools/original_data.lua restore) and brings their own cards.
-- Before anything is copied:
--   * every .pak is listed (UnrealPak -List): an asset converted from the original data stops the package; one that is
--     not tracked in git stops it too unless --allow names its folder (e.g. --allow Content/UniversityCity), so whoever
--     packs says what it is;
--   * the keys found on this machine (player.json files, the older deepseek.json / api-keys.json, DEEPSEEK_API_KEY,
--     DASHSCOPE_API_KEY) are searched for in every text file of the package: one found stops it.
-- --check stops after the report. The stage keeps its game files; its junctions into Content are not copied (the
-- launcher makes them on the first start, pointing at the package's own Content).
--
-- A private package (2026-11-12: a build for one tester, kept on this machine, never pushed or published):
--   --private            the original data the street reads goes in (Tools/original_data_manifest.json, all groups but
--                        --skip-group's, by default h-voices and studio-scenes), and original assets cooked into the
--                        paks no longer stop it; the tester needs no game of their own
--   --cards <folder>     only these OK cards: copied to Content/CharacterCards/StreetHeroines and made the default
--                        heroines (Launch/heroines.json, at most ten), with the male card (Launch/runtime.json male_card)
--   --roster <json>      with --cards: the default heroines are the cards this heroines.json lists (by file name, in
--                        its order) instead of the folder's first ten
--   --voice cloud        the new player's settings choose the cloud voices and voice input (keys still empty: ok-tts
--                        loads no local model until the key is typed into the settings)
--   --readme <file>      copied to the package's root
-- Keys still never go in.
--
-- An OK Studio-only package (--studio, 2026-11-16): a Studio*.stage (rebuild_street_social_runtime.lua --studio, only
-- /Engine/Maps/Entry and Template_Default cooked); OKStudio.cmd and CardReaderDevelopment.cmd (the card reader's
-- character editing) are the entries (no StreetSocial.cmd, no voice servers, no new player's street settings); the street's own data groups are left out by default (STUDIO_SKIP); --cards go to
-- Content/CharacterCards/<the folder's name>, the studio's card browser lists them. A street or city map in the paks
-- stops it.
--
-- Program and resources (Docs/PROGRAM_ONLY_UPDATE_PLAN.md, 2026-11-24): a file is a resource when it comes from outside
-- the code -- every path Tools/original_data_manifest.json lists, the cards (Content/CharacterCards/), the HairDeck
-- weights (HairDeckData/) and the resources' own record (Content/IndependentResources/RESOURCES.json); everything else
-- (the stage, Tools, launchers, Config, Docs, ModPackages, Plugins, Licenses, the self-made files under
-- Content/IndependentResources) is the program.
--   --program-only       only the program: laid over an installation that has the resources (its new stage is picked
--                        as the newest); no original data, no cards, and a resource file in the plan stops it
-- A package with the original data (--private, not --program-only) also gets Content/IndependentResources/RESOURCES.json:
-- what resources it carries (groups and their sizes, the library's oklib.json version, digests of shared_mods.txt and
-- mods_index.db), for the program to check its resources against.
local ok = require "ok"
local json, path, proc, util = ok.json, ok.path, ok.proc, ok.util
local player_settings = require "street_player_settings"
local street_stage = require "street_stage"

local function say(s) io.write(s, "\n"); io.flush() end
local function win(p) return (path.norm(p):gsub("/", "\\")) end
local function gb(n) return ("%.2f GB"):format(n / 1073741824) end

--
-- The mods (--mods <folder of .okmod>, 2026-11-23, Docs/OK_MOD_AUTHORING.md): the mods installed in the stage's Mods/
-- (ok-mod-pack profile apply ... --mods <stage>/Mods; its .old/ is left out) go to <stage>/Mods, where the packaged game
-- loads them; the .okmod packages to ModPackages/ (reinstall or pick another profile with ok-mod-pack); the mod sources
-- (Tools/ok-mod: the API, SDK, host, ok-mod-pack, every example and fixture; the ModKit content plugins
-- Plugins/org_openkoikatsu_*), ok-mod-pack.exe, and the mod documents (Docs/OK_MOD_*.md).
-- Files under the repository that git tracks (forward slashes, relative to the root).
local function tracked(root, specs)
  local args = { "git", "-C", root, "ls-files", "-z", "--" }
  for _, s in ipairs(specs) do args[#args + 1] = s end
  local r = proc.run(args, { capture = true, check = true })
  local out = {}
  for p in r.stdout:gmatch("([^%z]+)") do out[#out + 1] = p end
  return out
end

-- The stage to pack: --stage, else the newest usable one; the same rules as StreetSocial.cmd (Tools/street_stage.lua),
-- so the package's launcher accepts what is packed.
local function pick_stage(root, named, studio)
  local _, stage, name, how
  if named then _, stage, name, how = street_stage.named(root, named, "--stage")
  else _, stage, name, how = street_stage.newest(root, say, studio and "studio" or nil) end
  if stage and studio ~= street_stage.is_studio(name) then
    error(("--stage %s: %s"):format(name, studio and "--studio packs a Studio*.stage (rebuild --studio)" or "a Studio*.stage has no street map; pack it with --studio"), 0)
  end
  if stage then say(("Stage: %s (%s; %s)"):format(name, named and "--stage" or "newest", how)) end
  return stage
end

-- Every file under dir (following junctions), as {abs, rel}.
local function files_under(dir, skip)
  local out = {}
  local function visit(d, rel)
    for _, n in ipairs(path.list(d)) do
      local full, r = path.join(d, n), rel == "" and n or (rel .. "/" .. n)
      if not (skip and skip(r)) then
        if path.is_dir(full) then visit(full, r) else out[#out + 1] = { full, r } end
      end
    end
  end
  if path.is_dir(dir) then visit(dir, "") end
  return out
end

-- Build outputs inside a pak that are not assets (always fine).
local function pak_artifact(rel)
  return rel == "AssetRegistry.bin" or rel == "OpenKoikatsu.uproject" or rel:match("^Config/") or rel:match("%.upluginmanifest$")
    or rel:match("^Content/Shader") or rel:match("%.ushaderbytecode$") or rel:match("%.stinfo$") or rel:match("^Metadata/")
end

-- {original = {...}, untracked = {prefix -> count, example}, tracked = n} for the project entries of the paks.
local function check_paks(root, paks, allow)
  local engine = ok.engine_root()
  local unrealpak = path.join(engine, "Engine/Binaries/Win64/UnrealPak.exe")
  if not path.is_file(unrealpak) then error("UnrealPak not found: " .. win(unrealpak), 0) end
  local known = {}
  for _, p in ipairs(tracked(root, { "Content", "Plugins" })) do known[(p:gsub("%.[^./]+$", "")):lower()] = true end
  local original = {}
  local m = json.decode(path.read_text(path.join(root, "Tools/original_data_manifest.json")))
  for _, f in ipairs(m.files) do original[(f.path:gsub("%.[^./]+$", "")):lower()] = f.group end
  local report = { original = {}, untracked = {}, allowed = {}, tracked = 0, maps = {} }
  for _, pak in ipairs(paks) do
    local r = proc.run({ win(unrealpak), win(pak), "-List" }, { capture = true })
    if not r.ok then error("UnrealPak could not list " .. win(pak), 0) end
    for line in r.stdout:gmatch("[^\n]+") do
      local p = line:match('"([^"]+)" offset:')
      if p and p:lower():match("%.umap$") then report.maps[#report.maps + 1] = p end
      if p and p:match("^OpenKoikatsu/") then
        local rel = p:sub(#"OpenKoikatsu/" + 1)
        local key = (rel:gsub("%.[^./]+$", "")):lower()
        if original[key] then report.original[#report.original + 1] = rel .. " (" .. original[key] .. ")"
        elseif known[key] then report.tracked = report.tracked + 1
        elseif not pak_artifact(rel) then
          local top = rel:match("^([^/]+/[^/]+)") or rel
          local allowed = false
          for _, a in ipairs(allow) do if rel:sub(1, #a) == a then allowed = true end end
          local bucket = allowed and report.allowed or report.untracked
          local e = bucket[top] or { count = 0, example = rel }
          e.count = e.count + 1; bucket[top] = e
        end
      end
    end
  end
  return report
end

-- The keys on this machine, to make sure none of them is packed.
local function local_keys(root)
  local keys, seen = {}, {}
  local function add(v) if type(v) == "string" and #v >= 16 and not seen[v] then seen[v] = true; keys[#keys + 1] = v end end
  add(os.getenv("DEEPSEEK_API_KEY")); add(os.getenv("DASHSCOPE_API_KEY"))
  local function from(file)
    if not path.is_file(file) then return end
    local okj, v = pcall(function() return json.decode((path.read_text(file):gsub("^\239\187\191", ""))) end)
    if not okj or type(v) ~= "table" then return end
    add(v.api_key)
    for _, section in ipairs({ "deepseek", "aliyun" }) do if type(v[section]) == "table" then add(v[section].api_key) end end
  end
  local saved = path.join(root, "Saved/StreetSocial")
  for _, f in ipairs(files_under(saved, function(r) return r:match("^Build/") or r:match("^Play%-") or r:match("^TTSCache") end)) do
    local n = f[2]:lower()
    if n:match("player%.json$") or n:match("deepseek%.json") or n:match("api%-keys%.json") then from(f[1]) end
  end
  local user = os.getenv("LOCALAPPDATA") and path.join(os.getenv("LOCALAPPDATA"), "OpenKoikatsu")
  if user then for _, n in ipairs({ "player.json", "deepseek.json", "api-keys.json" }) do from(path.join(user, n)) end end
  return keys
end

-- Original data groups a Studio package leaves out unless --skip-group says otherwise: the street's dialogue, voices
-- and H poses, the H voices and the studio sample scenes (they carry characters). No size limit (user 2026-11-23):
-- the studio sound items (base-sounds, 2.3 GB) and the runtime clips (runtime-clips) go in; base-paired is the card
-- reader's game motion list.
local STUDIO_SKIP = { "h-voices", "studio-scenes", "street-voices", "street-dialogue", "h-poses" }

-- --mods: the stage's installed mods, the .okmod packages, the mod sources, ok-mod-pack and the mod documents.
-- counted(n) gets the number of installed mods.
local function package_mods(root, stage, stage_rel, packages, add, counted)
  local mods = path.join(stage, "Mods")
  if not path.is_file(path.join(mods, ".installed.toml")) then
    error("--mods: the stage has no installed mods (" .. win(mods) .. "); install them first, e.g. ok-mod-pack profile apply "
      .. "Tools/ok-mod/profiles/full.toml --mods " .. win(mods) .. " --packages " .. win(packages), 0)
  end
  local ids = {}
  for _, f in ipairs(files_under(mods, function(r) return r == ".old" end)) do
    add(f[1], stage_rel .. "/Mods/" .. f[2])
    local top = f[2]:match("^([^/]+)/mod%.toml$")
    if top then ids[#ids + 1] = top end
  end
  if not path.is_dir(packages) then error("--mods: no such folder of .okmod packages: " .. win(packages), 0) end
  local n_pkg = 0
  for _, name in ipairs(path.list(packages)) do
    if name:lower():match("%.okmod$") then add(path.join(packages, name), "ModPackages/" .. name); n_pkg = n_pkg + 1 end
  end
  local sources = { "Tools/ok-mod" }
  for _, rel in ipairs(tracked(root, { "Plugins" })) do
    local plugin = rel:match("^(Plugins/org_openkoikatsu_[^/]+)/")
    if plugin then add(path.join(root, rel), rel) end
  end
  for _, rel in ipairs(tracked(root, sources)) do add(path.join(root, rel), rel) end
  for _, rel in ipairs(tracked(root, { "Docs" })) do
    if rel:match("^Docs/OK_MOD_[^/]+%.md$") then add(path.join(root, rel), rel) end
  end
  local tool = "Tools/ok-mod/target/release/ok-mod-pack.exe"
  if not path.is_file(path.join(root, tool)) then error("--mods: " .. tool .. " is not built (cargo build --release -j 8 in Tools/ok-mod)", 0) end
  add(path.join(root, tool), tool)
  say(("Mods: %d installed in the stage (%s), %d packages"):format(#ids, table.concat(ids, ", "), n_pkg))
  counted(#ids)
end

-- Whether a package path is a resource (see the header): the manifest's paths (a set), the cards, HairDeck, RESOURCES.json.
local RESOURCES_FILE = "Content/IndependentResources/RESOURCES.json"
local function is_resource(rel, manifest_paths)
  return manifest_paths[rel] or rel:sub(1, 23) == "Content/CharacterCards/" or rel:sub(1, 13) == "HairDeckData/" or rel == RESOURCES_FILE
end

local TEXT_EXT = { json = true, txt = true, lua = true, ini = true, cmd = true, bat = true, toml = true, md = true, cfg = true, csv = true, tsv = true, xml = true, yaml = true, yml = true, log = true }

local function main()
  local p = ok.args.parser("Pack the street into a folder another player can run")
  p:opt("--out", { required = true })
  p:opt("--stage")
  p:opt("--zip")
  p:flag("--check")
  p:flag("--no-voice-servers")
  p:opt("--allow", { multiple = true })
  p:flag("--private")
  p:opt("--cards")
  p:opt("--max-cards")
  p:opt("--roster")
  p:opt("--voice")
  p:opt("--readme")
  p:opt("--skip-group", { multiple = true })
  p:flag("--studio")
  p:opt("--mods")
  -- --extra <source>=<package path>: a file or a whole folder put into the package as it is (data that is not in git:
  -- the HairDeck weights, a third-party license text; Tools/package_studio_release.lua).
  p:opt("--extra", { multiple = true })
  p:flag("--program-only")
  local a = p:parse(arg)
  if a.program_only and a.cards then error("--program-only takes no --cards (cards are resources)", 0) end
  local skip_groups = (a.skip_group and #a.skip_group > 0) and a.skip_group or (a.studio and STUDIO_SKIP or { "h-voices", "studio-scenes" })
  if a.voice and a.voice ~= "cloud" and a.voice ~= "builtin" then error("--voice must be cloud or builtin", 0) end
  local root = ok.root
  local out = path.abs(a.out):gsub("/+$", "")
  if out:sub(1, #root + 1) == root .. "/" then error("--out must be outside the repository: " .. win(out), 0) end
  if path.exists(out) and #path.list(out) > 0 and not a.check then error("--out must be a new or empty folder: " .. win(out), 0) end

  local stage = pick_stage(root, a.stage, a.studio)
  if not stage then
    error("No StreetSocial stage (Saved/StreetSocial/Build/*.stage); build one with Tools/rebuild_street_social_runtime.lua or pass --stage", 0)
  end
  local launch = json.decode(path.read_text(path.join(root, "Content/IndependentResources/StreetSocialData/Launch/runtime.json")))
  local patch = path.join(root, launch.patch)
  say("Stage: " .. win(stage))

  -- The files: {source, destination relative to out}.
  local plan, bytes = {}, 0
  local function add(src, rel) plan[#plan + 1] = { src, rel } end
  local stage_rel = "Saved/StreetSocial/Build/" .. path.name(stage)
  for _, f in ipairs(files_under(path.join(stage, "Windows"), function(r)
    return r == "OpenKoikatsu/Content/IndependentResources" or r == "OpenKoikatsu/Content/KKPreview" or r:match("^OpenKoikatsu/Saved")
      or r == "OpenKoikatsu/Content/CharacterCards" -- the scene editor's junction to this checkout's cards (run_scene_editor.lua)
  end)) do add(f[1], stage_rel .. "/Windows/" .. f[2]) end
  local paks = {}
  for _, f in ipairs(files_under(path.join(stage, "Windows/OpenKoikatsu/Content/Paks"))) do if f[1]:lower():match("%.pak$") then paks[#paks + 1] = f[1] end end
  -- The stage's own patch (X.stage/Patch, street_stage.own_patch) goes with it and is what its launcher mounts; else the
  -- shared one (Launch/runtime.json).
  local own = street_stage.own_patch(path.join(stage, "Windows/OpenKoikatsu/Binaries/Win64/OpenKoikatsu.exe"))
  if own then
    say("Runtime patch: the stage's own " .. win(own))
    for _, f in ipairs(files_under(own)) do
      add(f[1], stage_rel .. "/Patch/" .. f[2])
      if f[1]:lower():match("%.pak$") then paks[#paks + 1] = f[1] end
    end
  elseif path.is_dir(patch) then
    for _, f in ipairs(files_under(patch)) do
      add(f[1], launch.patch .. "/" .. f[2])
      if f[1]:lower():match("%.pak$") then paks[#paks + 1] = f[1] end
    end
  else say("Runtime patch missing (the player's launcher rebuilds it only with the editor): " .. win(patch)) end
  -- Versioned files: the launcher and its tools, the street's data, the settings guide.
  local versioned = a.studio
    and { "OKStudio.cmd", "CardReaderDevelopment.cmd", "Content/IndependentResources", "Tools/lua", "Config", "Tools/original_data_manifest.json",
      "Tools/base_library_shared_mods.txt", "Docs/SHARED_RESOURCES_SETUP.md", "Docs/STREET_SOCIAL_PACKAGE.md",
      "WriteMcpConfig.cmd", "Docs/CHARACTER_EDITOR_MCP_USAGE.md" }
    or { "StreetSocial.cmd", "OKStudio.cmd", "CardReaderDevelopment.cmd", "Content/IndependentResources", "Tools/lua", "Config",
      "Tools/original_data_manifest.json", "Tools/base_library_shared_mods.txt",
      "Docs/API_KEYS.md", "Docs/SHARED_RESOURCES_SETUP.md", "Docs/STREET_SOCIAL_PLAY_GUIDE.md", "Docs/STREET_SOCIAL_PACKAGE.md",
      "WriteMcpConfig.cmd", "Docs/CHARACTER_EDITOR_MCP_USAGE.md" }
  -- A Studio package leaves out the street's models and the runtime materials' uncooked sources (the game reads the
  -- cooked ones from its paks): half a gigabyte of the 10 GB it has to stay under.
  local studio_drop = { "Content/IndependentResources/StreetSocialData/Models/", "Content/IndependentResources/RuntimeMaterials/" }
  for _, rel in ipairs(tracked(root, versioned)) do
    local drop = false
    if a.studio then for _, prefix in ipairs(studio_drop) do if rel:sub(1, #prefix) == prefix then drop = true end end end
    if not drop then add(path.join(root, rel), rel) end
  end
  for _, rel in ipairs(tracked(root, { "Tools" })) do if rel:match("^Tools/[^/]+%.lua$") then add(path.join(root, rel), rel) end end
  -- Built tools the launcher and the restore use (the player has no cargo).
  for _, rel in ipairs({ "Tools/ok-rules/target/release/ok_rules.dll", "Tools/ok-mind/target/release/ok_mind.dll",
      "Tools/ok-story/target/release/ok_story.dll", "Tools/ok-extract/target/release/ok-extract.exe",
      -- Tools/lua/ok/kit.lua: the launcher's card checks (prepare_street_social_selection.lua) decode with it.
      "Tools/ok-luakit/target/release/ok-luakit.exe",
      -- The MCP servers an AI client drives the reader and OK Studio with (WriteMcpConfig.cmd writes their mcp.json).
      "Tools/ok-game-mcp/target/release/ok-game-mcp.exe", "Tools/character_mcp/bin/ok-character-mcp.exe",
      -- The reader's HairDeck hair (OKGalleryHairDeck.cpp, breeding's hair mix) and video import (OKVideoMotionPanel.cpp);
      -- a package takes the CPU build (cargo build --no-default-features: no CUDA on the player's machine). Their model
      -- weights are not packed (Tools/package_studio_release.lua says so).
      "Tools/ok-hairdeck/target/release/ok-hairdeck.exe", "Tools/ok-video/target/release/ok-video.exe" }) do
    if path.is_file(path.join(root, rel)) then add(path.join(root, rel), rel) else say("Not built, left out: " .. rel) end
  end
  for _, spec in ipairs(a.extra or {}) do
    local src, dest = spec:match("^(.-)=(.+)$")
    if not src or src == "" then error("--extra must be <source>=<package path>: " .. spec, 0) end
    src = path.abs(src)
    dest = dest:gsub("\\", "/"):gsub("^/+", ""):gsub("/+$", "")
    if dest:match("%.%.") then error("--extra package path must stay inside the package: " .. dest, 0) end
    if path.is_dir(src) then
      local files = files_under(src)
      for _, f in ipairs(files) do add(f[1], dest .. "/" .. f[2]) end
      say(("Extra: %s -> %s (%d files)"):format(win(src), dest, #files))
    elseif path.is_file(src) then add(src, dest); say(("Extra: %s -> %s"):format(win(src), dest))
    else error("--extra source missing: " .. win(src), 0) end
  end
  local mod_count = 0
  if a.mods then package_mods(root, stage, stage_rel, path.abs(a.mods), add, function(n) mod_count = n end) end
  if not a.no_voice_servers and not a.studio then
    for _, server in ipairs({ "ok-tts", "ok-asr" }) do
      local dir = path.join(root, "Build", server)
      if path.is_dir(dir) then
        -- Models are downloaded (ok-tts) or found by the player; logs and caches are this machine's.
        for _, f in ipairs(files_under(dir, function(r) return r == "models" or r == "logs" or r:match("^fit") or r:match("%.log$") end)) do
          add(f[1], "Build/" .. server .. "/" .. f[2])
        end
      else say("Voice server not built, left out: Build/" .. server) end
    end
  end
  -- Private: the original data (the tester has no game to restore it from). Not in a program-only package.
  local carried = {}
  if a.private and not a.program_only then
    local skip = {}
    for _, g in ipairs(skip_groups) do skip[g] = true end
    local m = json.decode(path.read_text(path.join(root, "Tools/original_data_manifest.json")))
    local have, missing, groups = 0, 0, {}
    for _, f in ipairs(m.files) do
      if not skip[f.group] then
        local src = path.join(root, f.path)
        if path.is_file(src) then add(src, f.path); have = have + 1; groups[f.group] = (groups[f.group] or 0) + f.bytes
          carried[f.group] = carried[f.group] or { files = 0, bytes = 0 }
          carried[f.group].files = carried[f.group].files + 1; carried[f.group].bytes = carried[f.group].bytes + f.bytes
        else missing = missing + 1 end
      end
    end
    local names = {}
    for g, n in pairs(groups) do names[#names + 1] = ("%s %s"):format(g, gb(n)) end
    table.sort(names)
    say(("Original data (private): %d files (%s); %d missing here; left out: %s"):format(have, table.concat(names, ", "), missing,
      table.concat(skip_groups, ", ")))
  end
  -- Private: only the given cards, and they are the heroines.
  local roster
  if a.cards then
    if not a.private then error("--cards needs --private (character cards never go into a public package)", 0) end
    local dir = path.abs(a.cards):gsub("/+$", "")
    local cards_rel = a.studio and ("Content/CharacterCards/" .. path.name(dir)) or "Content/CharacterCards/StreetHeroines"
    roster = json.array({})
    -- A Studio package takes the first --max-cards cards (default 10) to stay small; a street package takes them all.
    local max_cards = tonumber(a.max_cards) or (a.studio and 10 or math.huge)
    local taken = 0
    for _, n in ipairs(path.list(dir)) do
      if n:lower():match("%.png$") and taken < max_cards then
        taken = taken + 1
        local rel = cards_rel .. "/" .. n
        add(path.join(dir, n), rel)
        if #roster < 10 then roster[#roster + 1] = rel end
      end
    end
    if a.roster then
      -- The heroines in the order the given heroines.json has them (its cards must be in the folder).
      local want = json.decode(path.read_text(path.abs(a.roster))).cards or {}
      roster = json.array({})
      for _, c in ipairs(want) do
        local n = path.name(c)
        if not path.is_file(path.join(dir, n)) then error("--roster names a card not in " .. win(dir) .. ": " .. n, 0) end
        if #roster < 10 then roster[#roster + 1] = "Content/CharacterCards/StreetHeroines/" .. n end
      end
    end
    if #roster == 0 then error("no PNG cards in " .. win(dir), 0) end
    if path.is_file(path.join(root, launch.male_card)) then add(path.join(root, launch.male_card), launch.male_card)
    else say("Male card missing: " .. launch.male_card) end
    say(("Cards: %d heroines from %s"):format(#roster, win(dir)))
  end
  if a.readme then add(path.abs(a.readme), path.name(a.readme)) end
  -- Program-only: not one resource file goes in (an --extra of the weights, a manifest file that is also tracked...).
  local manifest_paths = {}
  for _, f in ipairs(json.decode(path.read_text(path.join(root, "Tools/original_data_manifest.json"))).files) do manifest_paths[f.path] = true end
  if a.program_only then
    local found = {}
    for _, e in ipairs(plan) do if is_resource(e[2], manifest_paths) then found[#found + 1] = e[2] end end
    if #found > 0 then error(("--program-only: %d resource file(s) in the plan, e.g. %s"):format(#found, found[1]), 0) end
    say("Program only: no original data, no cards, no HairDeck weights")
  end
  for _, e in ipairs(plan) do bytes = bytes + (path.size and path.size(e[1]) or 0) end

  -- Nothing original in the paks; nothing unaccounted for.
  local report = check_paks(root, paks, a.allow or {})
  say(("Paks: %d project assets tracked in git"):format(report.tracked))
  for top, e in pairs(report.allowed) do say(("  allowed (--allow): %d under %s, e.g. %s"):format(e.count, top, e.example)) end
  local stop = false
  if #report.original > 0 and a.private then
    say(("Private: %d assets converted from the original game data are in the paks (allowed)"):format(#report.original))
  elseif #report.original > 0 then
    stop = true
    say(("STOP: %d assets converted from the original game data are cooked into the paks:"):format(#report.original))
    for i = 1, math.min(#report.original, 20) do say("  " .. report.original[i]) end
    say("  Cook the stage without them (they must not be referenced by the street's maps) before packing.")
  end
  table.sort(report.maps)
  say(("Maps in the paks: %s"):format(#report.maps > 0 and table.concat(report.maps, ", ") or "none"))
  if a.studio then
    for _, m in ipairs(report.maps) do
      if m:match("^OpenKoikatsu/Content/Scenes/StreetSocial/") or m:match("^OpenKoikatsu/Content/UniversityCity/") then
        stop = true; say("STOP: a street or city map is in the studio's paks: " .. m)
      end
    end
  end
  for top, e in pairs(report.untracked) do
    stop = true
    say(("STOP: %d assets under %s are not tracked in git (e.g. %s); say what they are with --allow %s"):format(e.count, top, e.example, top))
  end

  -- No key of this machine in any text file.
  local keys = local_keys(root)
  local new_player = player_settings.template()
  if a.voice == "cloud" then new_player.voice.voice_mode = "cloud"; new_player.asr.mode = "cloud" end
  local template = player_settings.encode(new_player)
  local leaks = {}
  for _, e in ipairs(plan) do
    local ext = (e[2]:match("%.([%w]+)$") or ""):lower()
    if TEXT_EXT[ext] and (not path.size or path.size(e[1]) < 64 * 1048576) then
      local body = path.read_bytes and path.read_bytes(e[1]) or path.read_text(e[1])
      for _, k in ipairs(keys) do if body:find(k, 1, true) then leaks[#leaks + 1] = e[2] end end
    end
  end
  if not a.studio then
    for _, k in ipairs(keys) do if template:find(k, 1, true) then leaks[#leaks + 1] = "Saved/StreetSocial/player.json" end end
  end
  say(("Keys on this machine: %d, found in the package: %d"):format(#keys, #leaks))
  if #leaks > 0 then stop = true; for _, l in ipairs(leaks) do say("STOP: a key of this machine is in " .. l) end end

  say(("Package: %d files, %s"):format(#plan + 2, gb(bytes)))
  if a.check then say(stop and "Check: the package would stop here." or "Check: ready to pack."); os.exit(stop and 1 or 0) end
  if stop then error("Package stopped (see above)", 0) end

  path.mkdir(out, true)
  local free = path.disk_usage(out)
  if free and free.available and free.available < bytes * 1.05 then error(("Not enough room in %s: %s needed, %s free"):format(win(out), gb(bytes), gb(free.available)), 0) end
  for i, e in ipairs(plan) do
    local dst = path.join(out, e[2])
    path.mkdir(path.parent(dst), true)
    path.copy(e[1], dst)
    if i % 2000 == 0 then say(("  %d / %d files"):format(i, #plan)) end
  end
  -- The stage's stage.json: the launcher skips a stage without it (fbbea3d69 / e936b8ba0; 2026-11-15 the package
  -- copied only Windows/ and would not start). This machine's host and base paths are left out.
  do
    local okj, m = pcall(json.decode, path.read_text(path.join(stage, "stage.json")))
    if not okj or type(m) ~= "table" or not tonumber(m.staged_at) then error("The stage has no usable stage.json: " .. win(stage), 0) end
    path.write_text(path.join(out, stage_rel, "stage.json"), json.encode(json.object({ { "staged_at", tonumber(m.staged_at) },
      { "staged_at_text", m.staged_at_text or "" }, { "commit", m.commit or "" }, { "dirty", m.dirty and true or false } }),
      { indent = 2 }) .. "\n", { newline = "\n" })
  end
  -- A new player's settings: built-in voices, no keys (they fill them in the settings menu at the top left).
  if not a.studio then
    path.mkdir(path.join(out, "Saved/StreetSocial"), true)
    path.write_text(path.join(out, "Saved/StreetSocial/player.json"), template, { newline = "\n" })
  end
  if roster and not a.studio then
    local file = path.join(out, "Content/IndependentResources/StreetSocialData/Launch/heroines.json")
    path.write_text(file, json.encode(json.object({ { "note", "This package's heroines (Tools/package_street_social.lua --cards)." }, { "cards", roster } }),
      { indent = 2, ensure_ascii = false }) .. "\n", { newline = "\n" })
  end
  local listing = json.array({})
  for _, e in ipairs(plan) do listing[#listing + 1] = e[2] end
  -- The resources' record (a package with the original data): what it carries, read from the files themselves. Which of
  -- these a program needs, and how it says so, is the compatibility gate's (Docs/PROGRAM_ONLY_UPDATE_PLAN.md).
  local kind = a.program_only and "program" or (next(carried) and "full" or "no-resources")
  if kind == "full" then
    local hash = require "ok.hash"
    local lib = "Content/IndependentResources/base_v1"
    local parts = {}
    local okj, marker = pcall(json.decode, path.read_text(path.join(out, lib, "oklib.json")))
    if okj and type(marker) == "table" then parts[#parts + 1] = { "oklib_version", marker.version } end
    for _, f in ipairs({ "shared_mods.txt", "mods_index.db" }) do
      local file = path.join(out, lib, f)
      if path.is_file(file) then parts[#parts + 1] = { f, json.object({ { "bytes", path.size(file) }, { "sha256", hash.sha256_file(file) } }) } end
    end
    local names = {}
    for g in pairs(carried) do names[#names + 1] = g end
    table.sort(names)
    local groups = {}
    for _, g in ipairs(names) do groups[#groups + 1] = { g, json.object({ { "files", carried[g].files }, { "bytes", carried[g].bytes } }) } end
    path.write_text(path.join(out, RESOURCES_FILE), json.encode(json.object({ { "format", "ok-resources" }, { "schema", 1 },
      { "made", os.date("!%Y-%m-%dT%H:%M:%SZ") }, { "package", path.name(out) },
      { "commit", util.strip(proc.run({ "git", "-C", root, "rev-parse", "HEAD" }, { capture = true }).stdout) },
      { "groups", json.object(groups) }, { "parts", json.object(parts) } }), { indent = 1 }) .. "\n", { newline = "\n" })
    listing[#listing + 1] = RESOURCES_FILE
    say("Resources: " .. RESOURCES_FILE .. " (" .. table.concat(names, ", ") .. ")")
  end
  path.write_text(path.join(out, "PACKAGE.json"), json.encode(json.object({ { "schema", 1 }, { "made", os.date("!%Y-%m-%dT%H:%M:%SZ") },
    { "stage", path.name(stage) }, { "commit", util.strip(proc.run({ "git", "-C", root, "rev-parse", "HEAD" }, { capture = true }).stdout) },
    { "mode", a.studio and "studio" or "street" }, { "kind", kind }, { "private", a.private and true or false },
    { "skip_groups", json.array(a.private and skip_groups or {}) }, { "maps_in_paks", json.array(report.maps) },
    { "mods", mod_count },
    { "cook", a.studio and "/Engine/Maps/Entry + Template_Default + DirectoriesToAlwaysCook (rebuild_street_social_runtime.lua --studio)"
      or "StreetSocial + UniversityCity maps + DirectoriesToAlwaysCook (rebuild_street_social_runtime.lua)" },
    { "files", listing } }), { indent = 1, ensure_ascii = false }) .. "\n", { newline = "\n" })
  say("Packed into " .. win(out))
  if a.zip then
    local zip = path.abs(a.zip)
    -- 7-Zip when it is installed: Windows' tar crashed (0xC0000005) zipping a 16 GB package with a Chinese file name.
    local seven = "C:/Program Files/7-Zip/7z.exe"
    if path.is_file(seven) then
      proc.run({ win(seven), "a", "-tzip", "-mx=1", "-mmt=8", win(zip), win(out) .. "\\*" }, { check = true })
      -- Read back once before it is handed on (a zip of tens of GB nobody tested is not delivered, 2026-11-24).
      proc.run({ win(seven), "t", "-mmt=8", win(zip) }, { check = true })
      say("Zip tested (7z t): " .. win(zip))
    else
      proc.run({ "tar", "-a", "-c", "-f", win(zip), "-C", win(out), "." }, { check = true })
      say("Zip not tested: 7-Zip is not installed (" .. win(seven) .. ")")
    end
    say("Zip: " .. win(zip))
  end
end

main()
