-- What a HairDeck result actually contains, so two reference pictures can be compared without opening a card
-- (Docs/HAIRDECK.md). The numbers are in HairDeck's head frame: +y up, +z towards the face, the skull about 0.5 W wide.
--
--   Tools\lua\lua.exe Tools\hairdeck_stats.lua <cards_seed0.json>...
--
-- Prints per file: strands, control points, the box the strands fill, how far the lowest strand hangs below the crown,
-- and how much of the head's circumference they go round (strands behind the ears vs in front of them).
local ok = require "ok"
local json, path = ok.json, ok.path

for _, file in ipairs({ ... }) do
  local cards = json.decode(path.read_text(file))
  local n, points = #cards, 0
  local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
  local behind, front = 0, 0
  for _, card in ipairs(cards) do
    local seq = card.seq or {}
    points = points + #seq
    local back = false
    for _, p in ipairs(seq) do
      for i = 1, 3 do
        lo[i] = math.min(lo[i], p[i]); hi[i] = math.max(hi[i], p[i])
      end
      if p[3] < 0 then back = true end
    end
    if back then behind = behind + 1 else front = front + 1 end
  end
  if n == 0 then print(("HAIRDECK %s\tno strands"):format(file))
  else
    print(("HAIRDECK %s\tstrands=%d points=%d x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f] drop=%.3f behind=%d front=%d"):format(
      file, n, points, lo[1], hi[1], lo[2], hi[2], lo[3], hi[3], hi[2] - lo[2], behind, front))
  end
end
