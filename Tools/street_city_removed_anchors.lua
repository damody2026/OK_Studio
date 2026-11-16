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
}
-- Rooms dropped from a place: place id -> { { at = {x, y}, why } }, the room whose box holds `at` (xy) goes.
local ROOMS = {
  bike_shop = { { at = { 30200, 32740 }, why = 'S81, 116 m from the door at S35' } },
}
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
  rooms = ROOMS, room_gone = room_gone, apart_cm = APART_CM, apart_ok = APART_OK }
