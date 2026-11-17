-- Anchors whose furniture was taken off the source map: dropped from city_places.json (Tools/export_street_city_game_places.lua)
-- and from city_anchors.json (both that exporter, in place, and Tools/build_street_city_places.lua when it is re-run), so
-- no schedule or activity sends anyone to a seat that is not there. place id -> { anchor name -> why }.
-- Also rooms left out of a place (ROOMS) and the "a place is one building with its door" check's exceptions (APART_OK).
--   local REMOVED = dofile('Tools/street_city_removed_anchors.lua'); if REMOVED.gone(place, name) then ... end
-- The generators' other exception list: Tools/street_city_moved_props.lua, props moved (not removed) on the source map
-- after the install, whose anchors move with them. This one drops anchors, that one shifts them.
local GONE = {
  -- KTV_2 (S48 唱片小室) removed 11-15, Tools/street_city_ktv_remove_payload.lua: its seats (sofa) and its screen
  karaoke = { seat2 = 'KTV_2 removed', seat14 = 'KTV_2 removed', seat15 = 'KTV_2 removed', screen2 = 'KTV_2 removed' },
  -- bike_shop was two shops 116 m apart (S35, S81; street_city_lover_spots_payload.lua joins them) with the door only at S35:
  -- a girl sent to S81's racks was walked to S35's door first. S81 is left out (11-16, coordinator), its room below.
  bike_shop = { bike_rental3 = 'S81 left out of bike_shop', bike_rental4 = 'S81 left out of bike_shop' },
  -- the pool suite's 'pool' (h_pool, motel_203_imore-cda5d5e2dcb9) is 195 cm over the 2F floor (z 1901), over a corridor
  -- and lounge with no pool or water (seen in the game 11-17, c3b1117a): a floor of its own no lift or stair reaches
  -- (the reach check's B3). Not brought down: on the floor it would be a pool activity in a corridor.
  hotel = { pool = 'no pool under it: 195 cm over the 2F corridor' },
  -- school became one T1 ground-floor classroom (19ab3abcf); its 'music' (music_piano, 69961,41953,2020) stayed where the
  -- old school was, in the SC building's 3F (cafeteria's room there), 80 m from T1: tagged T1, a floor of the school no
  -- stair or lift of T1 reaches (the reach check's last floor without an entry, 11-17). 42 other music_piano anchors.
  school = { music = 'left from the old school, in the SC building 3F, not T1' },
}
-- Rooms dropped from a place: place id -> { { at = {x, y}, why } }, the room whose box holds `at` (xy) goes.
local ROOMS = {
  bike_shop = { { at = { 30200, 32740 }, why = 'S81, 116 m from the door at S35' } },
}
-- The place's name once a room is left out (the game says "arrived at <name>").
local NAMES = { bike_shop = '單車行（S35 城市單車）' }
-- A place is one building: an indoor place's rooms are joined by chains of indoor rooms (of any place) each within
-- APART_CM of the next (xy, any floor), and the door's room is in that one chain. Places allowed to be apart, with why
-- (the exporter lists the rest as problems).
local APART_CM = 1000
local APART_OK = {}
local function room_gone(place, room)
  for _, r in ipairs(ROOMS[place] or {}) do
    if room.min and r.at[1] >= room.min[1] and r.at[1] <= room.max[1] and r.at[2] >= room.min[2] and r.at[2] <= room.max[2] then return r.why end
  end
end
return { list = GONE, gone = function(place, name) local p = GONE[place]; return p and p[name] or nil end,
  rooms = ROOMS, room_gone = room_gone, names = NAMES, apart_cm = APART_CM, apart_ok = APART_OK }
