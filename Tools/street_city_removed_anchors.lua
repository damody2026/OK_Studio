-- Anchors whose furniture was taken off the source map: dropped from city_places.json (Tools/export_street_city_game_places.lua)
-- and from city_anchors.json (both that exporter, in place, and Tools/build_street_city_places.lua when it is re-run), so
-- no schedule or activity sends anyone to a seat that is not there. place id -> { anchor name -> why }.
--   local REMOVED = dofile('Tools/street_city_removed_anchors.lua'); if REMOVED.gone(place, name) then ... end
local GONE = {
  -- KTV_2 (S48 唱片小室) removed 11-15, Tools/street_city_ktv_remove_payload.lua: its seats (sofa) and its screen
  karaoke = { seat2 = 'KTV_2 removed', seat14 = 'KTV_2 removed', seat15 = 'KTV_2 removed', screen2 = 'KTV_2 removed' },
}
return { list = GONE, gone = function(place, name) local p = GONE[place]; return p and p[name] or nil end }
