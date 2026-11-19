-- Record which executable a batch of screenshots (or measurements) came from, so two batches are only compared when
-- they came from the same build. Writes <out>/batch_header.json; `check` compares two headers.
--
--   Tools\lua\lua.exe Tools\shot_batch_header.lua write --exe <path to the .exe that took the shots> --out <batch dir> [--label <name>]
--   Tools\lua\lua.exe Tools\shot_batch_header.lua check <batch dir A> <batch dir B>
--
-- Three things, because each alone has misled us (2026-11-19, E group): the exe's mtime and size (two runs without them
-- had to be thrown away as a baseline), HEAD, and a fingerprint of the working tree (`git status --porcelain` plus the
-- full `git diff HEAD`): in a shared tree the same HEAD builds different executables, because other sessions'
-- uncommitted edits get compiled in. A rebuild in the middle of a session makes the earlier "before" shots useless:
-- `check` then says DIFFERENT and those batches must be shot again.
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

local function header(exe, label)
  local attr = lfs.attributes(exe)
  if not attr or attr.mode ~= "file" then error("not an executable file: " .. tostring(exe)) end
  local porcelain = git("status --porcelain")
  local diff = git("diff HEAD --no-color")
  return {
    label = label,
    written_at = os.date("%Y-%m-%d %H:%M:%S"),
    exe = { path = exe, mtime = os.date("%Y-%m-%d %H:%M:%S", attr.modification), mtime_epoch = attr.modification, size = attr.size },
    head = (git("rev-parse HEAD"):gsub("%s+$", "")),
    tree = {
      clean = porcelain == "",
      status_hash = hash_text(porcelain),
      diff_hash = hash_text(diff),
      changed_files = select(2, porcelain:gsub("\n", "")),
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
  local opts = {}
  local i = 2
  while arg[i] do opts[arg[i]:gsub("^%-%-", "")] = arg[i + 1]; i = i + 2 end
  assert(opts.exe and opts.out, "usage: write --exe <exe> --out <batch dir> [--label <name>]")
  lfs.mkdir(opts.out)
  local h = header(opts.exe, opts.label)
  local f = assert(io.open(opts.out .. "/batch_header.json", "wb")); f:write(json.encode(h)); f:close()
  print(("batch header: exe %s (%s, %d bytes) HEAD %s tree %s"):format(h.exe.path, h.exe.mtime, h.exe.size, h.head:sub(1, 9),
    h.tree.clean and "clean" or (h.tree.changed_files .. " changed files, diff " .. h.tree.diff_hash:sub(1, 9))))
elseif mode == "check" then
  local a, b = read(arg[2] or ""), read(arg[3] or "")
  if not a or not b then print("MISSING: a batch without batch_header.json cannot be compared with another"); os.exit(2) end
  local same = a.exe.mtime_epoch == b.exe.mtime_epoch and a.exe.size == b.exe.size and a.head == b.head
    and a.tree.status_hash == b.tree.status_hash and a.tree.diff_hash == b.tree.diff_hash
  if same then print("SAME build: the two batches can be compared") else
    print("DIFFERENT build: do not compare these batches")
    for _, k in ipairs({ "exe.mtime_epoch", "exe.size", "head", "tree.status_hash", "tree.diff_hash" }) do
      local x, y = a, b
      for part in k:gmatch("[^.]+") do x = x and x[part]; y = y and y[part] end
      if x ~= y then print(("  %s: %s vs %s"):format(k, tostring(x), tostring(y))) end
    end
    os.exit(1)
  end
else
  print("usage: shot_batch_header.lua write --exe <exe> --out <dir> [--label <name>] | check <dirA> <dirB>")
  os.exit(2)
end
