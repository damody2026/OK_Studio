-- Record which executable a batch of screenshots (or measurements) came from, so two batches are only compared when
-- they came from the same build. Writes <out>/batch_header.json; `check` compares two headers.
--
--   Tools\lua\lua.exe Tools\shot_batch_header.lua write (--editor <project root> | --exe <binary> [--exe <binary>...]) --out <batch dir> [--label <name>]
--   Tools\lua\lua.exe Tools\shot_batch_header.lua check <batch dir A> <batch dir B>
--
-- `check` exit codes, each answer its own: 0 SAME (comparable), 1 DIFFERENT, 2 MISSING (a folder has no header),
-- 3 OLD (a header from the whole-tree version: not compared at all). Only 0 means "compare them". Read the code of
-- this command itself — in `check … | tee log` the shell reports tee's 0, which is how an OLD once looked like a pass.
--
-- What is compared, because each alone has misled us (2026-11-19, E group): the binaries' mtime and size (two runs
-- without them had to be thrown away as a baseline), and a fingerprint of the PROGRAM content only — the paths that end
-- up in the reader (`PROGRAM_PATHS`): their committed ids at HEAD plus `git status --porcelain` and `git diff HEAD`
-- limited to them. In a shared tree the same HEAD builds different executables (other sessions' uncommitted edits get
-- compiled in), so the uncommitted part counts. The first version hashed the WHOLE tree, and a commit of a `Docs/`
-- file made two batches from the same executable DIFFERENT — it threw away good data. So:
-- * `Docs`, `Saved` and the shot output folders are not part of the fingerprint;
-- * HEAD is recorded but does not decide: a docs commit moves HEAD and not the program, uncommitted C++ moves the
--   program and not HEAD. HEAD alone never identifies an executable; the committed ids plus the uncommitted part do.
-- A rebuild in the middle of a session makes the earlier "before" shots useless: `check` then says DIFFERENT and those
-- batches must be shot again.
--
-- Self-test record (a gauge's output only counts after it was checked on known-positive and known-negative samples;
-- E group rule 7, 2026-11-19). 2026-11-19, F tree, exe Binaries/Win64/OpenKoikatsu.exe:
--   * two `write`s of the same exe and tree → `check` SAME (exit 0)  — known positive;
--   * one header's exe.mtime_epoch changed  → `check` DIFFERENT (exit 1), lists `exe.mtime_epoch` — known negative;
--   * a folder without a header              → `check` MISSING (exit 2).
--   The first run found a real fault: `os.tmpname()` on Windows gives "\s1n7g." (drive root), and the status hash came
--   back empty with no error; it now uses %TEMP% and fails when git returns no hash.
--   Again after `--editor` (9 editor modules, F tree): SAME (0); the project DLL's mtime changed in one header →
--   DIFFERENT (1) naming that DLL; no header → MISSING (2). Keep both hashes: `git diff HEAD`
--   does not see untracked files, `git status --porcelain` does.
--   Again after narrowing to the program paths (2026-11-19, F tree, `--editor`, 9 binaries; every check prints its
--   denominator, "compared 17 items … N differ"):
--   * run on the current tree: it listed 3 uncommitted changes, all program files (OKExtractBuildStamp.h,
--     ok-extract/src/entries.rs, this tool); untracked UserData/ and Docs/ were not listed — acceptance;
--   * two writes → SAME (0 of 17 differ);
--   * an untracked file added under Docs/ between the writes → SAME (0 of 17) — a docs change no longer voids a batch;
--   * HEAD changed in one header → SAME, with the HEAD line printed as "not compared";
--   * an untracked file added under Tools/ → DIFFERENT (1 of 17: uncommitted status_hash), exit 1 — known negative;
--   * a header from the whole-tree version → OLD (exit 3, its own code since 2026-11-19: it shared 2 with MISSING, and
--     one run piped through a pager read as exit 0); no header → MISSING (exit 2).
--
-- Which binaries: the card reader runs the ENGINE's UnrealEditor.exe with the project (run_card_reader_development.lua),
-- and the engine is never rebuilt — its mtime says nothing. What our builds change are the project's editor modules, and
-- not only the project one: ok-extract (Rust) is linked into Plugins/KKUnityBundle's UnrealEditor-KKUnityBundle.dll, so
-- a Rust-only change leaves UnrealEditor-OpenKoikatsu.dll as it was. `--editor <root>` therefore records
-- Binaries/Win64/UnrealEditor-*.dll and every Plugins/KK*/Binaries/Win64/UnrealEditor-*.dll. A packaged run records its
-- own OpenKoikatsu.exe with `--exe`; the two ways of running are never compared with each other.
--
-- mtime + size, not a content hash, on purpose: a relink that leaves the bytes the same still gives DIFFERENT, and a
-- batch gets shot again for nothing. That errs the right way (one extra batch beats two batches from different
-- programs side by side), and hashing nine modules of hundreds of MB for every batch is not worth it. So a DIFFERENT
-- after a no-op rebuild is the tool doing its job, not a bug.
--
-- Run it right after the build that produced the exe and before shooting — the tree may change while you shoot. It
-- runs git only (no build, no cargo), so it is fine while `may-build` says wait.
local lfs = require("lfs")
local json = require("ok.json")

local function sh(cmd)
  local p = assert(io.popen(cmd, "r")); local out = p:read("a"); p:close(); return out
end
local function git(args) return sh("git " .. args .. " 2>NUL") end
-- git's own content hash of a string (no Lua SHA needed): the same text always gives the same id.
local seq = 0
local function hash_text(text)
  -- Not os.tmpname(): on Windows it gives a drive-root name like "\s1n7g." that may not be writable, and the hash
  -- then came back empty without an error.
  seq = seq + 1
  local tmp = (os.getenv("TEMP") or ".") .. ("\\shot_batch_header_%d_%d.txt"):format(os.time(), seq)
  local f = assert(io.open(tmp, "wb")); f:write(text); f:close()
  local id = sh('git hash-object --no-filters "' .. tmp .. '" 2>NUL'):gsub("%s+$", "")
  os.remove(tmp)
  if id == "" then error("git hash-object failed for " .. tmp) end
  return id
end

local function binary(path)
  local attr = lfs.attributes(path)
  if not attr or attr.mode ~= "file" then error("not a file: " .. tostring(path)) end
  return { path = path, mtime = os.date("%Y-%m-%d %H:%M:%S", attr.modification), mtime_epoch = attr.modification, size = attr.size }
end
-- The project's editor modules: Binaries/Win64 and each Plugins/KK*/Binaries/Win64, UnrealEditor-*.dll, sorted.
local function editor_binaries(root)
  local out = {}
  local function scan(dir)
    if lfs.attributes(dir, "mode") ~= "directory" then return end
    for n in lfs.dir(dir) do if n:match("^UnrealEditor%-.+%.dll$") then out[#out + 1] = dir .. "/" .. n end end
  end
  scan(root .. "/Binaries/Win64")
  for p in lfs.dir(root .. "/Plugins") do if p:match("^KK") then scan(root .. "/Plugins/" .. p .. "/Binaries/Win64") end end
  table.sort(out)
  if #out == 0 then error("no editor modules under " .. root) end
  return out
end
-- What is compiled or read into the reader: C++ (Source, Plugins with their .Build.cs), ok-extract and the launch
-- scripts (Tools, with Cargo.*), runtime config (Config: DefaultGame.ini, ReaderEditor/pages.json), assets and text
-- (Content: maps, Localization), and the .uproject. Character cards are inputs, not the program; built binaries are
-- what `binaries` records.
local PROGRAM_PATHS = { "Source", "Plugins", "Tools", "Config", "Content", "OpenKoikatsu.uproject" }
local EXCLUDE = { "Content/CharacterCards", "Plugins/*/Binaries", "Plugins/*/Intermediate" }
local function pathspec()
  local parts = {}
  for _, p in ipairs(PROGRAM_PATHS) do parts[#parts + 1] = '"' .. p .. '"' end
  for _, p in ipairs(EXCLUDE) do parts[#parts + 1] = '":(exclude)' .. p .. '"' end
  return table.concat(parts, " ")
end
local function header(paths, label)
  local bins = {}
  for _, p in ipairs(paths) do bins[#bins + 1] = binary(p) end
  local spec = pathspec()
  local porcelain = git("status --porcelain -- " .. spec)
  local diff = git("diff HEAD --no-color -- " .. spec)
  local committed = {}
  for _, p in ipairs(PROGRAM_PATHS) do committed[p] = (git("rev-parse HEAD:" .. p):gsub("%s+$", "")) end
  local changed = {}
  for line in porcelain:gmatch("[^\n]+") do changed[#changed + 1] = line end
  return {
    label = label,
    written_at = os.date("%Y-%m-%d %H:%M:%S"),
    exe = bins[1],
    binaries = bins,
    head = (git("rev-parse HEAD"):gsub("%s+$", "")),
    program = {
      paths = PROGRAM_PATHS, exclude = EXCLUDE,
      committed = committed,
      clean = porcelain == "",
      status_hash = hash_text(porcelain),
      diff_hash = hash_text(diff),
      changed = changed,
    },
  }
end

local function read(dir)
  local f = io.open(dir .. "/batch_header.json", "rb")
  if not f then return nil end
  local h = json.decode(f:read("a")); f:close(); return h
end

local mode = arg[1]
if mode == "write" then
  local opts, exes = {}, {}
  local i = 2
  while arg[i] do
    local k = arg[i]:gsub("^%-%-", "")
    if k == "exe" then exes[#exes + 1] = arg[i + 1] else opts[k] = arg[i + 1] end
    i = i + 2
  end
  if opts.editor then for _, p in ipairs(editor_binaries(opts.editor)) do exes[#exes + 1] = p end end
  assert(#exes > 0 and opts.out, "usage: write (--editor <root> | --exe <binary>...) --out <batch dir> [--label <name>]")
  lfs.mkdir(opts.out)
  local h = header(exes, opts.label)
  local f = assert(io.open(opts.out .. "/batch_header.json", "wb")); f:write(json.encode(h)); f:close()
  print(("batch header: %d binaries, first %s (%s, %d bytes); HEAD %s (recorded, not compared)"):format(#h.binaries, h.exe.path,
    h.exe.mtime, h.exe.size, h.head:sub(1, 9)))
  -- The uncommitted program files, every one: whoever reads this sees what was compiled in besides HEAD.
  print(("program: %d of %d paths, %d uncommitted changes%s"):format(#PROGRAM_PATHS, #PROGRAM_PATHS, #h.program.changed,
    #h.program.changed == 0 and " (clean)" or ":"))
  for _, line in ipairs(h.program.changed) do print("  " .. line) end
elseif mode == "check" then
  local a, b = read(arg[2] or ""), read(arg[3] or "")
  if not a or not b then print("MISSING: a batch without batch_header.json cannot be compared with another"); os.exit(2) end
  if not a.program or not b.program then
    print("OLD header: written by the whole-tree version (a Docs commit changed it). Write it again with this version;")
    print("if the tree has not changed since, that is the same batch, not a new one."); os.exit(3)
  end
  -- Every recorded binary, by path: one module rebuilt is a different build.
  local function bins(h) local t = {} for _, x in ipairs(h.binaries or { h.exe }) do t[x.path] = x end return t end
  local ba, bb = bins(a), bins(b)
  local bin_diff = {}
  for p, x in pairs(ba) do local y = bb[p]; if not y or y.mtime_epoch ~= x.mtime_epoch or y.size ~= x.size then bin_diff[#bin_diff + 1] = p end end
  for p in pairs(bb) do if not ba[p] then bin_diff[#bin_diff + 1] = p end end
  table.sort(bin_diff)
  local diffs = {}
  for _, p in ipairs(bin_diff) do diffs[#diffs + 1] = "binary differs or is missing on one side: " .. p end
  local paths = {}
  for p in pairs(a.program.committed) do paths[#paths + 1] = p end
  for p in pairs(b.program.committed) do if a.program.committed[p] == nil then paths[#paths + 1] = p end end
  table.sort(paths)
  for _, p in ipairs(paths) do
    if a.program.committed[p] ~= b.program.committed[p] then diffs[#diffs + 1] = ("committed %s: %s vs %s"):format(p, tostring(a.program.committed[p]), tostring(b.program.committed[p])) end
  end
  for _, k in ipairs({ "status_hash", "diff_hash" }) do
    if a.program[k] ~= b.program[k] then diffs[#diffs + 1] = ("uncommitted %s: %s vs %s"):format(k, a.program[k], b.program[k]) end
  end
  -- A count with its denominator: "0 differ" alone cannot be told from "nothing was compared".
  local nbin = 0
  for _ in pairs(ba) do nbin = nbin + 1 end
  for p in pairs(bb) do if not ba[p] then nbin = nbin + 1 end end
  local compared = nbin + #paths + 2
  print(("compared %d items (%d binaries, %d committed program paths, 2 uncommitted hashes): %d differ"):format(compared, nbin, #paths, #diffs))
  if a.head ~= b.head then print(("  HEAD %s vs %s (not compared: a commit outside the program paths moves it)"):format(a.head:sub(1, 9), b.head:sub(1, 9))) end
  if #diffs == 0 then print("SAME build: the two batches can be compared") else
    print("DIFFERENT build: do not compare these batches")
    for _, d in ipairs(diffs) do print("  " .. d) end
    os.exit(1)
  end
else
  print("usage: shot_batch_header.lua write --exe <exe> --out <dir> [--label <name>] | check <dirA> <dirB>")
  os.exit(2)
end
