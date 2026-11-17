-- Repeatable open-card timing: runs ok-card-open-bench --sequence over a fixed sample set,
-- N rounds in separate processes, and reports the median per card plus the stage breakdown
-- of one profiled round. Every round is a fresh process, so each open is an uncached one
-- (OK_NOCACHE, as the reader opens cards since 2026-10-28).
--   Tools\lua\lua.exe Tools\card_open_bench.lua --out <dir> [--rounds 3] [--label name] [--card <path>]...
local lfs = require("lfs")
local ROOT = (os.getenv("OK_ROOT") or "."):gsub("\\", "/")
local BENCH = ROOT .. "/Tools/ok-extract/target/release/ok-card-open-bench.exe"
local LIB = ROOT .. "/Content/IndependentResources/base_v1"
-- The samples: a light OK card, two heavy ones, a hand-made reference card, and the demo male.
local DEFAULT = {
  ROOT .. "/Content/CharacterCards/CrowdAPNG/C006.png",
  ROOT .. "/Content/CharacterCards/CrowdAPNG/C001.png",
  ROOT .. "/Content/CharacterCards/CrowdAPNG/C049.png",
  ROOT .. "/Content/CharacterCards/RefCards20261109/klara.png",
  ROOT .. "/Content/CharacterCards/Demo/C050.png",
}
local args, out, rounds, label, cards = { ... }, nil, 3, "run", {}
local i = 1
while i <= #args do
  local a = args[i]
  if a == "--out" then i = i + 1; out = args[i]
  elseif a == "--rounds" then i = i + 1; rounds = tonumber(args[i])
  elseif a == "--label" then i = i + 1; label = args[i]
  elseif a == "--card" then i = i + 1; cards[#cards + 1] = args[i]
  else error("unknown argument: " .. a) end
  i = i + 1
end
assert(out, "--out <dir> is required")
if #cards == 0 then cards = DEFAULT end
local function mkdirp(p)
  local acc = nil
  for part in p:gsub("\\", "/"):gmatch("[^/]+") do
    acc = acc and (acc .. "/" .. part) or part
    if acc:match("^%a:$") then acc = acc .. "/" else lfs.mkdir(acc) end
  end
end
mkdirp(out)
local function run(cmd)
  local f = assert(io.popen(cmd .. " 2>&1", "r"))
  local text = f:read("a"); f:close(); return text
end
-- ok-card-open-bench prints "<card>@<outfit> <seconds>s" per open on stderr.
local function timings(text)
  local seen = {}
  for card, secs in text:gmatch("ok%-card%-open%-bench: ([^%s]+)@%d+ ([%d.]+)s") do
    local name = card:gsub(".*[/\\]", "")
    seen[#seen + 1] = { card = name, seconds = tonumber(secs) }
  end
  return seen
end
local quoted = {}
for _, c in ipairs(cards) do quoted[#quoted + 1] = '"' .. c .. '"' end
local base = string.format('set "RAYON_NUM_THREADS=8" && "%s" --sequence "%s" %s',
  BENCH:gsub("/", "\\"), LIB:gsub("/", "\\"), table.concat(quoted, " "):gsub("/", "\\"))
local per_card = {}
for r = 1, rounds do
  local text = run("cmd /c " .. base)
  local rows = timings(text)
  if #rows == 0 then io.stderr:write(text); error("no timings in round " .. r) end
  for _, row in ipairs(rows) do
    per_card[row.card] = per_card[row.card] or {}
    table.insert(per_card[row.card], row.seconds)
  end
  io.write(string.format("round %d done\n", r)); io.flush()
end
-- One extra profiled round for the stage breakdown.
local profiled = run('cmd /c set "RAYON_NUM_THREADS=8" && set "OK_PROFILE=1" && ' .. base:gsub('^set "RAYON_NUM_THREADS=8" && ', ""))
local pf = assert(io.open(out .. "/" .. label .. "-profile.txt", "w")); pf:write(profiled); pf:close()
local function median(t)
  table.sort(t)
  local n = #t
  if n % 2 == 1 then return t[(n + 1) // 2] end
  return (t[n // 2] + t[n // 2 + 1]) / 2
end
local names = {}
for k in pairs(per_card) do names[#names + 1] = k end
table.sort(names)
local lines, total = {}, 0
lines[#lines + 1] = string.format("# %s (%d rounds, median seconds per uncached open)\n", label, rounds)
lines[#lines + 1] = "| card | median s | min | max |\n|---|---:|---:|---:|\n"
for _, name in ipairs(names) do
  local t = per_card[name]
  local m = median(t)
  total = total + m
  lines[#lines + 1] = string.format("| %s | %.3f | %.3f | %.3f |\n", name, m, t[1], t[#t])
end
lines[#lines + 1] = string.format("| **sum** | **%.3f** | | |\n", total)
local text = table.concat(lines)
local f = assert(io.open(out .. "/" .. label .. ".md", "w")); f:write(text); f:close()
io.write(text)
