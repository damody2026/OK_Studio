-- The standard cold card-open baseline: one command that says whether the open path got slower.
--
--   Tools\lua\lua.exe Tools\card_open_baseline.lua [-Cards DIR] [-Library DIR] [-Rounds N]
--     [-Warmup N] [-Out FILE] [-Compare FILE|latest] [-NoBuild]
--
-- Why this exists: the open path is within about 13% of what its architecture allows (Docs/CARD_OPEN_PERF_20261117.md),
-- so the value now is not squeezing another 2% out of it but **not letting it quietly get slower**. Anyone who touches
-- the open path runs this and compares against the last run.
--
-- What it measures, and why exactly this way (the traps are the first three sections of that doc):
--   * Only cold opens. The on-disk open cache stays off for good, so there is no "warm" baseline to compare with.
--   * The reader's own cold path: `ok-card-open-bench --sequence` with OK_BENCH_PREWARM=concurrent, so the startup
--     prewarm runs beside the first card the way the app does it. Plain mode pays for work the app has prewarmed away
--     and puts the bottleneck in the wrong place.
--   * The six representative cards of that doc's correctness set, in a fixed order, in one process per round: the
--     second card onwards also measures what the first left behind.
--   * Several rounds, median per card. One run against one run is not a comparison.
--   * At most 8 threads (RAYON_NUM_THREADS=8), like every other build and measurement in this project.
--   * Besides time it records `OK_PROFILE`'s work counts ("from scratch N, R repeat"), which do not care how busy the
--     machine is: on a noisy machine the counts still say whether a change really made the open do less, while the
--     times do not. Counts locate, time decides.
local ok = require "ok"
local path = require "ok.path"
local proc = require "ok.proc"
local json = require "ok.json"

local root = path.parent(path.parent(path.abs(arg[0])))

-- The fixed set: OK 卡 C001／C006／C049／C050 ＋ klara ＋ megumin (Docs/CARD_OPEN_PERF_20261117.md 第三节). Fixed on
-- purpose — a baseline whose input moves measures nothing. Names, not paths: cards never enter version control.
local CARDS = {
  "crowd_C001.png", "crowd_C006.png", "crowd_C049.png",
  "demo_C050.png", "heroine_klara.png", "heroine_megumin.png",
}
local DEFAULT_CARDS = { "E:/OKPackage/TestCards-20261118", root .. "/Content/CharacterCards/CrowdAPNG" }
local USAGE = [[
Tools\lua\lua.exe Tools\card_open_baseline.lua [-Cards DIR] [-Library DIR] [-Rounds N]
  [-Out FILE] [-Compare FILE|latest] [-NoBuild]
]]

-- Option names as the rest of this project writes them (-Name value, case-insensitive), like
-- run_card_reader_development.lua rather than ok.args's --name style.
local VALUES = { cards = true, library = true, rounds = true, out = true, compare = true, warmup = true }
local SWITCHES = { nobuild = true, help = true }
local o = {}
do
  local i = 1
  while i <= #arg do
    local a = arg[i]
    local name, inline = a:match("^%-%-?([%a%-]+)[:=](.*)$")
    if not name then name = a:match("^%-%-?([%a%-]+)$") end
    if not name then error(("unexpected argument %q\n%s"):format(a, USAGE)) end
    name = name:lower():gsub("%-", "")
    if VALUES[name] then
      local value = inline
      if not value then i = i + 1; value = arg[i] end
      if not value then error(("-%s needs a value\n%s"):format(name, USAGE)) end
      o[name] = value
    elseif SWITCHES[name] then
      o[name] = true
    else
      error(("unknown option %q\n%s"):format(a, USAGE))
    end
    i = i + 1
  end
end
if o.help then print(USAGE) return end
-- 5 rounds plus one discarded warm-up (below). Calibration, 2026-11-19, idle machine: WITHOUT a warm-up round
-- successive runs drifted 6.90 → 6.17 → 6.03 s (the OS file cache warming up), and two 2-round runs differed by
-- 7.7% on the total and 17% on one card; WITH the warm-up, three runs of 3 rounds gave 6.01 / 5.95 / 6.00 s —
-- about 1%. So treat a total change over about 3% as real and anything under it as noise. The work count was
-- 472-475 across every one of those runs, which is why it is the number to gate on.
local rounds = tonumber(o.rounds) or 5
if rounds < 1 then error("-Rounds must be at least 1") end
local library = path.norm(o.library or (root .. "/Content/IndependentResources/base_v1"))
if not path.is_dir(library) then
  error(("base library not found: %s\nGive -Library, or restore it (Tools/original_data.lua restore)."):format(library))
end

-- The cards folder: the one given, else the first default that holds every baseline card.
-- The run to compare against is read **before** this run writes anything: -Compare latest means the previous run's
-- latest.json, and reading it afterwards would compare this run with itself (every row +0.0%, measured 2026-11-19).
local latest = root .. "/Saved/Reports/card-open-baseline/latest.json"
local before, before_path
if o.compare then
  before_path = o.compare == "latest" and latest or path.norm(o.compare)
  if not path.is_file(before_path) then
    error(("-Compare %s: no such run (the first run has nothing to compare with)"):format(before_path))
  end
  before = json.decode(path.read_bytes(before_path))
end

local cards_dir
if o.cards then
  cards_dir = path.norm(o.cards)
else
  for _, dir in ipairs(DEFAULT_CARDS) do
    if path.is_dir(dir) then
      local all = true
      for _, name in ipairs(CARDS) do if not path.is_file(dir .. "/" .. name) then all = false end end
      if all then cards_dir = dir break end
    end
  end
  cards_dir = cards_dir or DEFAULT_CARDS[1]
end
-- Missing cards are an error with their names, never a quiet shorter run: a baseline of four cards is not comparable
-- with one of six, and nothing in the numbers would say so (Docs/ERROR_LOG.md, the io.popen entry).
local paths, missing = {}, {}
for _, name in ipairs(CARDS) do
  local full = cards_dir .. "/" .. name
  if path.is_file(full) then paths[#paths + 1] = full else missing[#missing + 1] = name end
end
if #missing > 0 then
  error(("%d of the %d baseline cards are missing from %s:\n  %s\nGive -Cards <folder> that holds all of them.")
    :format(#missing, #CARDS, cards_dir, table.concat(missing, "\n  ")))
end

local exe = root .. "/Tools/ok-extract/target/release/ok-card-open-bench.exe"
if not o.nobuild then
  print("building ok-card-open-bench (-j 8)...")
  proc.run({ "cargo", "build", "--release", "-j", "8", "--bin", "ok-card-open-bench",
             "--manifest-path", root .. "/Tools/ok-extract/Cargo.toml" }, { check = true })
end
if not path.is_file(exe) then error("not built: " .. exe) end

local function median(list)
  if #list == 0 then return nil end
  local s = {}
  for i, v in ipairs(list) do s[i] = v end
  table.sort(s)
  local mid = #s // 2
  if #s % 2 == 1 then return s[mid + 1] end
  return (s[mid] + s[mid + 1]) / 2
end

-- One round: one process, the six cards in order, the prewarm beside the first card.
local function round(n)
  if n > 0 then io.write(("round %d/%d "):format(n, rounds)) end
  io.flush()
  local call = { exe, "--sequence", library }
  for _, c in ipairs(paths) do call[#call + 1] = c end
  local r = proc.run(call, { capture = true, env = {
    OK_BENCH_PREWARM = "concurrent", RAYON_NUM_THREADS = "8", OK_PROFILE = "1", OK_THREADS = "8",
  } })
  if not r.ok then
    io.write("\n")
    error(("ok-card-open-bench failed (%d):\n%s"):format(r.code, (r.stderr or ""):sub(-2000)))
  end
  local body = json.decode(r.stdout)
  local seconds = {}
  for _, row in ipairs(body.sequence or {}) do
    seconds[path.name(row.card)] = row.seconds
  end
  -- Stage rows and work counts from OK_PROFILE on stderr. Summed per round, median across rounds.
  local stages, scratch, repeats = {}, nil, nil
  for line in (r.stderr or ""):gmatch("[^\n]+") do
    local label, ms = line:match("^ok%-extract: PROFILE (.-)%s+([%d.]+)ms")
    if label and not label:match("^ ") then
      label = label:gsub("%s+$", "")
      stages[label] = (stages[label] or 0) + tonumber(ms)
    end
    local total, rep = line:match("^ok%-extract: PROFILE from scratch (%d+) %((%d+) repeat%)")
    if total then scratch = (scratch or 0) + tonumber(total); repeats = (repeats or 0) + tonumber(rep) end
  end
  local total = 0
  for _, s in pairs(seconds) do total = total + s end
  io.write(("%.2fs\n"):format(total))
  return { seconds = seconds, stages = stages, scratch = scratch, repeats = repeats, total = total }
end

-- One discarded warm-up round. The open cache is off for good, but the OS file cache for the base library is not:
-- measured 2026-11-19 on an idle machine, successive 5-round runs drifted 6.90 → 6.17 → 6.03 s as the bundles stayed
-- in the OS cache. Dropping the first round takes that drift out of the median instead of leaving it in the number.
local warmup = tonumber(o.warmup) or 1
local runs, warmup_totals = {}, {}
for i = 1, warmup do
  io.write("warm-up (discarded) ")
  warmup_totals[i] = round(0).total
end
for i = 1, rounds do runs[i] = round(i) end

-- Medians.
local per_card, totals, stage_med = {}, {}, {}
for _, name in ipairs(CARDS) do
  local list = {}
  for _, r in ipairs(runs) do if r.seconds[name] then list[#list + 1] = r.seconds[name] end end
  per_card[name] = median(list)
end
for _, r in ipairs(runs) do totals[#totals + 1] = r.total end
local stage_names = {}
for _, r in ipairs(runs) do for label in pairs(r.stages) do stage_names[label] = true end end
for label in pairs(stage_names) do
  local list = {}
  for _, r in ipairs(runs) do list[#list + 1] = r.stages[label] or 0 end
  stage_med[label] = median(list)
end
local scratch_list, repeat_list = {}, {}
for _, r in ipairs(runs) do
  if r.scratch then scratch_list[#scratch_list + 1] = r.scratch end
  if r.repeats then repeat_list[#repeat_list + 1] = r.repeats end
end

local git = proc.run({ "git", "-C", root, "rev-parse", "--short", "HEAD" }, { capture = true, hide = true })
local result = {
  schema = 1,
  when = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  commit = (git.stdout or ""):gsub("%s+$", ""),
  library = library,
  cards_dir = cards_dir,
  cards = CARDS,
  rounds = rounds,
  warmup_rounds = warmup,
  warmup_total_seconds = warmup_totals,
  per_card_median_seconds = per_card,
  total_median_seconds = median(totals),
  total_seconds_each_round = totals,
  stage_median_ms = stage_med,
  from_scratch_median = median(scratch_list),
  repeat_median = median(repeat_list),
}

print("")
print(("card open baseline — %d rounds, %s, commit %s"):format(rounds, path.name(cards_dir), result.commit))
for _, name in ipairs(CARDS) do print(("  %-22s %6.2f s"):format(name, per_card[name] or 0)) end
print(("  %-22s %6.2f s  (each round: %s)"):format("TOTAL (median)", result.total_median_seconds or 0,
  (function() local t = {} for i, v in ipairs(totals) do t[i] = ("%.2f"):format(v) end return table.concat(t, ", ") end)()))
if result.from_scratch_median then
  print(("  work from scratch %d (%d repeat) — this number does not care how busy the machine is")
    :format(result.from_scratch_median, result.repeat_median or 0))
end
-- The stages worth watching, biggest first. The whole table is in the JSON.
local ordered = {}
for label, ms in pairs(stage_med) do ordered[#ordered + 1] = { label = label, ms = ms } end
table.sort(ordered, function(a, b) return a.ms > b.ms end)
print("  slowest stages (summed over the six cards, median round):")
for i = 1, math.min(8, #ordered) do print(("    %-34s %8.0f ms"):format(ordered[i].label, ordered[i].ms)) end

local out = o.out and path.norm(o.out)
if not out then
  local dir = root .. "/Saved/Reports/card-open-baseline"
  path.mkdir(dir, true)
  out = dir .. "/" .. os.date("!%Y%m%d-%H%M%S") .. ".json"
end
path.write_bytes(out, json.encode(result, { indent = 2, sort_keys = true }))
path.mkdir(path.parent(latest), true)
path.write_bytes(latest, json.encode(result, { indent = 2, sort_keys = true }))
print("")
print("written: " .. out)
print("latest:  " .. latest)

if before then
  print("")
  print(("against %s (commit %s, %d rounds):"):format(path.name(before_path), before.commit or "?", before.rounds or 0))
  local function delta(label, now, then_)
    if not now or not then_ or then_ == 0 then return end
    local pct = (now - then_) / then_ * 100
    print(("  %-22s %6.2f → %6.2f s  %+5.1f%%%s"):format(label, then_, now, pct, pct > 5 and "   SLOWER" or ""))
  end
  for _, name in ipairs(CARDS) do delta(name, per_card[name], (before.per_card_median_seconds or {})[name]) end
  delta("TOTAL", result.total_median_seconds, before.total_median_seconds)
  if result.from_scratch_median and before.from_scratch_median then
    print(("  work from scratch %d → %d (%+d)"):format(before.from_scratch_median, result.from_scratch_median,
      result.from_scratch_median - before.from_scratch_median))
  end
  print("  With the warm-up round, 3+ rounds on an idle machine repeat to about 1%: read a total change over ~3%")
  print("  as real, under it as noise;")
  print("  per-card numbers are noisier. The work count is deterministic — that is the one to trust, and the")
  print("  only one worth reading at all while another Unreal process is running.")
end
