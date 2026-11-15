-- Which anchors are upstairs in a street-level place that has no way up: one rule for the two tables the game reads, the
-- places (Tools/export_street_city_game_places.lua -> city_places.json, the heroines' schedule) and the rules' anchors
-- (Tools/build_street_city_places.lua -> city_anchors.json, acts and H), so the two never judge it differently.
-- A place counts when it is indoors, its door is at street level (under 13 m) and none of its anchors is a lift* or
-- stair*: the game finds a floor's way up by those (OKStreetPlaceLifts), so nothing walks up there (the cafe's 2F seats,
-- c-conquest nh1115y, 2026-11-15). An anchor 2.5 m or more over the door is off; 3 m or more is a real floor (3.8 m a
-- storey), less is something high indoors. school is a campus building reached through campus_t1's lifts.
--   local U = dofile('Tools/street_city_upstairs_off.lua')(places)   -- places: { id, door, outdoor, rooms, anchors }
--   U.off(place_id, pos)  -> nil, or { floor = n, real = bool } for an anchor of that place at pos
--   U.mark(row)           -> renames row.name off_<name> once (true when it was marked now)
--   U.unmark(row)         -> renames off_<name> back to <name> (true when it was off)
--   U.PREFIX              -> 'off_'
local PREFIX, SKIP = 'off_', { school = true }
return function(places)
  local by = {}
  for _, p in ipairs(places) do
    if not p.outdoor and not SKIP[p.id] and type(p.door) == 'table' and #p.door == 3 and p.door[3] < 1300 then
      local lifted = false
      for _, an in ipairs(p.anchors or {}) do local n = an.name:gsub('^' .. PREFIX, ''); if n:match('^lift') or n:match('^stair') then lifted = true end end
      if not lifted then by[p.id] = p end
    end
  end
  local U = { PREFIX = PREFIX }
  function U.off(id, pos)
    local p = by[id]; if not p or type(pos) ~= 'table' or not pos[3] then return nil end
    local dz = pos[3] - p.door[3]; if dz < 250 then return nil end
    local fl
    for _, room in ipairs(p.rooms or {}) do if room.min and room.max and pos[1] >= room.min[1] and pos[1] <= room.max[1]
      and pos[2] >= room.min[2] and pos[2] <= room.max[2] and pos[3] >= room.min[3] - 50 and pos[3] < room.max[3] then fl = room.floor end end
    -- the ground-floor room of a shop often reaches 4 m up, over its 2F (z 1580)
    if dz >= 300 and (not fl or fl < 2) then fl = math.floor(dz / 380 + .5) + 1 end
    return { floor = fl, real = dz >= 300 }
  end
  function U.mark(row)
    if row.name:sub(1, #PREFIX) == PREFIX then return false end
    row.name = PREFIX .. row.name; return true
  end
  -- Back to its own name once the place has a way up (Tools/street_city_shop_stairs.lua, 11-16): true when it was off.
  function U.unmark(row)
    if row.name:sub(1, #PREFIX) ~= PREFIX then return false end
    row.name = row.name:sub(#PREFIX + 1); return true
  end
  return U
end
