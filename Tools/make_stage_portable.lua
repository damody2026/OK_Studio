-- Makes a staged build folder self-contained, so it can be copied to another machine and run there without the
-- checkout, the base or a compile: every junction inside it (Engine/Binaries, Content/Paks -> the base,
-- Content/IndependentResources -> the project, ...) is replaced by a real folder of hard links to the same files.
-- Hard links cost no extra disk here and become ordinary files when the folder is copied; a target on another volume is
-- copied instead.
--
--   Tools\lua\lua.exe Tools\make_stage_portable.lua <STAGE\Windows> [--dry-run]
--
-- Local scratch never ships: base_v1/work (conversion work folders) and the *.okpreview replay caches beside the base
-- library. Character cards are not under the linked folders; put the ones to take along next to the build yourself.
local ok = require "ok"
local path, proc = ok.path, ok.proc
local lfs = require "lfs"

-- Paths (relative to a junction's target, lower case, "/") left out of the portable copy.
local function skipped(rel)
  rel = rel:lower()
  if rel:match("^base_v1/work/") or rel == "base_v1/work" then return true end
  if rel:match("^base_v1/[^/]+%.okpreview$") then return true end
  return false
end

-- Junctions (and directory symlinks) under dir, deepest first, with their targets: read from each entry's own attributes
-- (lfs.symlinkattributes: mode "link" for a reparse point, and its target), never followed. This used to parse `dir /s
-- /al`'s English or Traditional Chinese text; under another language or code page it found none, and the copy below
-- would have gone through the junctions and filled the stage with the whole base. What cannot be told is an error, not
-- "no junction": an entry without attributes, a link without its target, a kind we do not know.
local function junctions(dir)
  local found = {}
  local function walk(d)
    local okd, iter, state = pcall(lfs.dir, d)
    if not okd then error("Cannot list " .. d .. ": " .. tostring(iter), 0) end
    for e in iter, state do
      if e ~= "." and e ~= ".." then
        local p = path.join(d, e)
        local a, why = lfs.symlinkattributes(p)
        if not a then error("Cannot read the attributes of " .. p .. ": " .. tostring(why), 0) end
        if a.mode == "link" then
          if not a.target or a.target == "" then error("A link without a readable target: " .. p, 0) end
          found[#found + 1] = { path = p, target = a.target }
        elseif a.mode == "directory" then walk(p)
        elseif a.mode ~= "file" then error("Unknown kind " .. tostring(a.mode) .. ": " .. p, 0) end
      end
    end
  end
  walk(dir)
  table.sort(found, function(a, b) return #a.path > #b.path end)
  return found
end

local function mirror(src, dst, rel, stats, dry)
  if not dry then path.mkdir(dst, true) end
  for _, n in ipairs(path.list(src)) do
    local a, b = path.join(src, n), path.join(dst, n)
    local r = rel == "" and n or (rel .. "/" .. n)
    if not skipped(r) then
      -- A link inside the target is not followed (it could lead anywhere, the whole base): stop and say where.
      local attr = lfs.symlinkattributes(a)
      if not attr then error("Cannot read the attributes of " .. a, 0) end
      if attr.mode == "link" then error("A link inside a junction's target, not followed: " .. a .. " -> " .. tostring(attr.target), 0) end
      if attr.mode == "directory" then mirror(a, b, r, stats, dry)
      else
        stats.files = stats.files + 1
        stats.bytes = stats.bytes + (path.size(a) or 0)
        if not dry then
          local linked = lfs.link(a, b)
          if not linked then path.copy(a, b); stats.copied = stats.copied + 1 end
        end
      end
    else stats.skipped = stats.skipped + 1 end
  end
end

local function main()
  local dir, dry = nil, false
  for _, a in ipairs(arg) do
    if a:lower() == "--dry-run" or a:lower() == "-dryrun" then dry = true
    elseif not dir then dir = path.abs(a)
    else error("unexpected argument: " .. a, 0) end
  end
  if not dir or not path.is_dir(dir) then error("usage: make_stage_portable.lua <STAGE\\Windows> [--dry-run]", 0) end
  local list = junctions(dir)
  if #list == 0 then io.write("No junctions under ", dir, ": already self-contained.\n"); return end
  local total = { files = 0, bytes = 0, copied = 0, skipped = 0 }
  for _, j in ipairs(list) do
    local stats = { files = 0, bytes = 0, copied = 0, skipped = 0 }
    local target = path.abs(j.target)
    if not path.is_dir(target) then error("Junction target missing: " .. j.path .. " -> " .. target, 0) end
    if not dry then
      -- rd without /s removes only the junction itself, never the target's files.
      local r = proc.run({ "cmd", "/c", "rd", (j.path:gsub("/", "\\")) }, { capture = true })
      if not r.ok or path.exists(j.path) then error("Could not remove junction " .. j.path, 0) end
    end
    mirror(target, j.path, "", stats, dry)
    io.write(("%s %s <- %s: %d files, %.2f GiB%s%s\n"):format(dry and "would link" or "linked", j.path, target, stats.files,
      stats.bytes / 2 ^ 30, stats.copied > 0 and (", copied " .. stats.copied) or "", stats.skipped > 0 and (", left out " .. stats.skipped) or ""))
    for k, v in pairs(stats) do total[k] = total[k] + v end
  end
  io.write(("%s: %d files, %.2f GiB (%d left out)\n"):format(dry and "Dry run" or "Done", total.files, total.bytes / 2 ^ 30, total.skipped))
end

ok.main(main)
