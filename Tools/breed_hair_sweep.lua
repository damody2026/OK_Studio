-- Breed several pairs of cards and check the children's hair (Docs/OK_BREEDING.md).
--
--   Tools\lua\lua.exe Tools\breed_hair_sweep.lua [-Cards DIR] [-Pairs N] [-Out DIR] [-Library base_v1]
--     [-Exe ok-extract.exe] [-Game GAME_ROOT]
--
-- Every child is bred, then opened with `--oklib hair-check`, which both refuses a child a cooked game would draw
-- bald and prints how the hair sits on her head (fit scale, the hair's extent against the head's). The sweep fails
-- when any child fails, so it can stand in a packaging self-check or a regression run.
local ok = require "ok"
local path, proc = ok.path, ok.proc

local function parse(argv)
  local o, i = { pairs = 6 }, 1
  while i <= #argv do
    local k = (argv[i] or ""):gsub("^%-%-?", ""):lower()
    local v = argv[i + 1]
    if k == "cards" then o.cards = v; i = i + 2
    elseif k == "pairs" then o.pairs = tonumber(v) or 6; i = i + 2
    elseif k == "out" then o.out = v; i = i + 2
    elseif k == "library" then o.library = v; i = i + 2
    elseif k == "exe" then o.exe = v; i = i + 2
    elseif k == "game" then o.game = v; i = i + 2
    else error("unknown option: " .. tostring(argv[i])) end
  end
  return o
end

local o = parse({ ... })
o.cards = o.cards or path.join(ok.root, "Content/CharacterCards/StreetHeroines")
o.out = o.out or path.join(ok.root, "Saved/BreedHairSweep")
o.exe = o.exe or path.join(ok.root, "Tools/ok-extract/target/release/ok-extract.exe")
o.library = o.library or path.join(ok.root, "Content/IndependentResources/base_v1")
o.game = o.game or "X:/NoGame"

local cards = {}
for _, p in ipairs(path.glob(o.cards, "*.png")) do cards[#cards + 1] = p end
table.sort(cards)
if #cards < 2 then error("need at least two cards in " .. o.cards) end
path.mkdir(o.out, true)

local env = { OK_BASE_LIBRARY = o.library, RAYON_NUM_THREADS = "8", OK_NOCACHE = "1" }
local failed, lines = 0, {}
for n = 1, o.pairs do
  local mother = cards[((n - 1) * 2) % #cards + 1]
  local father = cards[((n - 1) * 2 + 1) % #cards + 1]
  local seed = tostring(1000 + n)
  local child = path.join(o.out, string.format("%s_x_%s_%s.png", path.stem(mother), path.stem(father), seed))
  local r = proc.run({ o.exe, o.game, "--oklib", "breed", mother, father, seed, child }, { env = env, capture = true })
  if not r.ok then
    failed = failed + 1
    lines[#lines + 1] = string.format("BREED fail\t%s x %s\t%s", path.name(mother), path.name(father),
      ((r.stderr or "") .. (r.stdout or "")):gsub("%s+$", ""):sub(-400))
  else
    local c = proc.run({ o.exe, o.game, "--oklib", "hair-check", child }, { env = env, capture = true })
    local line = ((c.stdout or "") .. (c.stderr or "")):match("OKHAIRCHECK[^\n\r]*") or "OKHAIRCHECK fail\t(no output)"
    if line:match("^OKHAIRCHECK fail") then failed = failed + 1 end
    lines[#lines + 1] = line
  end
end

for _, l in ipairs(lines) do print(l) end
print(string.format("BREEDHAIRSWEEP pairs=%d failed=%d out=%s", o.pairs, failed, o.out))
if failed > 0 then os.exit(1) end
