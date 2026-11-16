-- Props the lover-spots install placed (Tools/street_city_lover_spots_payload.lua) and that were moved afterwards on the
-- source map, because they shut a way through. Shared by:
--   Tools/street_city_props_move_payload.lua  moves the actors on the source map (via the session script's props-move.json)
--   Tools/export_street_city_game_places.lua  moves their anchors in city_anchors.json (in place) and city_places.json
--   Tools/build_street_city_places.lua        moves their anchors when the table is rebuilt from the install receipt
-- The generators' other exception list: Tools/street_city_removed_anchors.lua, furniture taken off the source map, whose
-- anchors are dropped. This one shifts anchors, that one drops them.
-- Each: prefix =the actors' labels; from = where the group's main actor (prefix .. main) stood, x y; delta = x y z cm;
-- anchors = { { place, name } } that stood by the prop, moved with it (only when still at their install position).
local M = {}
M.list = {
  -- clinic_gyn: the waiting room east of the hall (bench, seat seat2 seat3 seat26; x 32475-32865, y 57105-57565) opens
  -- only on its +y side (x 32635-32725) onto the crib corner, where crib3 (x 32684-32804, y 57605-57665) left 45 cm to
  -- that wall (y 57560): no 40 cm box got through, the game never reached the bench in any stage (c-conquest 11-16,
  -- room survey 11-16). 40 cm along +y: 85 cm to the wall; the cubicles at y 57775 end at x 32585, west of it; crib2
  -- (x 32588-32648) untouched.
  { prefix = 'LoverSpot_R2_fixtures_crib3', main = '_Tripo', from = { 32744, 57635 }, delta = { 0, 40, 0 },
    anchors = { { place = 'clinic_gyn', name = 'crib3', from = { 32744.0, 57694.8 } } } },
  -- The S-shop restrooms' way out (Tools/street_city_reach_check.lua, 11-16: clothing_s10, swimwear and supermarket
  -- toilets sealed): the shells' restroom vestibule opens onto the shop, but the install's dress() kept only the door
  -- and the door swings clear, and stood these pieces in the vestibule's mouth or the passage behind it. dress() keeps no
  -- way from the door to the anchors; this list mends the map as installed, and after an install
  -- Tools/street_city_reach_check.lua gate (run first by Tools/build_street_city_stream.lua) stops a map that seals
  -- anchors again. Fixed here in the data, not in the generator: the install is not re-run. Each new spot is
  -- off the shop floor the door already reached, 60 cm clear of the place's anchors, every cell within 40 cm of it free,
  -- and closing those cells takes nothing else off the door's region (the game's 40 cm grid, reach grid 11-16).
  -- clothing_s10: the bench (180 cm along y) filled the 2 m vestibule's west mouth (x 48227-48273, y 32310-32490).
  { prefix = 'LoverSpot_R2_clothing_s10_seatbench1_', main = 'Seat', from = { 48250, 32400 }, delta = { -530, -200, 0 },
    anchors = { { place = 'clothing_s10', name = 'seat', from = { 48255.0, 32355.0 } },
      { place = 'clothing_s10', name = 'seat2', from = { 48255.0, 32445.0 } } } },
  -- swimwear (S58): the bench stood across the corner where the vestibule's passage turns to the back (y 33653-33699).
  { prefix = 'LoverSpot_R2_swimwear_seatbench1_', main = 'Seat', from = { 34316.255, 33676.559 }, delta = { -376, -436, 0 },
    anchors = { { place = 'swimwear', name = 'seat', from = { 34361.255, 33681.559 } },
      { place = 'swimwear', name = 'seat2', from = { 34271.255, 33681.559 } } } },
  -- supermarket (S72): the extra checkout counter closed the vestibule's west mouth (x 34430-34497, y 50778-50944); it
  -- goes by the entrance (its cashier spot is not a game anchor: 'checkout' is the refit's own till at 34300,50580).
  { prefix = 'LoverSpot_R2_supermarket_checkout1_', main = 'Counter', from = { 34463.587, 50861.325 }, delta = { -904, -401, 0 } },
  -- and the cart stood in the one gap from the sales floor to the back passage (x 34194-34282, y 50961-51013).
  { prefix = 'LoverSpot_R2_supermarket_cart1_', main = 'Basket', from = { 34237.857, 50987.117 }, delta = { -18, -627, 0 },
    anchors = { { place = 'supermarket', name = 'cart', from = { 34167.857, 50987.117 } } } },
}
-- the anchor's position after the move, or nil when the row is not one of these (or already moved)
function M.shift(place, name, pos)
  for _, m in ipairs(M.list) do
    for _, a in ipairs(m.anchors or {}) do
      if a.place == place and a.name == name and pos and math.abs(pos[1] - a.from[1]) < 5 and math.abs(pos[2] - a.from[2]) < 5 then
        return { pos[1] + m.delta[1], pos[2] + m.delta[2], pos[3] + m.delta[3] }
      end
    end
  end
end
-- the rest of a moved anchor or item goes by the same offset (old pos -> new pos): where she sits (seat_pos, an item's
-- seat) and a pair's slots. Without it the stand spot moved and she still sat down on the old bench (11-16, C1 benches).
function M.carry(t, from, to)
  local dx, dy, dz = to[1] - from[1], to[2] - from[2], to[3] - from[3]
  local function mv(v) if type(v) == 'table' and v[1] then return { v[1] + dx, v[2] + dy, v[3] + dz } end; return v end
  t.seat_pos, t.seat = mv(t.seat_pos), mv(t.seat)
  for _, k in ipairs({ 'slots', 'pair' }) do if type(t[k]) == 'table' then
    for _, s in ipairs(t[k]) do s.pos, s.seat_pos, s.seat = mv(s.pos), mv(s.seat_pos), mv(s.seat) end end end
end
-- an install receipt item (lover-spots-install-*.json: actor, pos) after the move, or nil
function M.shift_item(actor, pos)
  for _, m in ipairs(M.list) do
    if actor and actor:sub(1, #m.prefix) == m.prefix and pos then
      for _, a in ipairs(m.anchors or {}) do
        if math.abs(pos[1] - a.from[1]) < 5 and math.abs(pos[2] - a.from[2]) < 5 then
          return { pos[1] + m.delta[1], pos[2] + m.delta[2], pos[3] + m.delta[3] }
        end
      end
    end
  end
end
return M
