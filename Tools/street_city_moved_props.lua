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
