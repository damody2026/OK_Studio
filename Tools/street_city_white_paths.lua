local f=assert(io.open('Tools/street_city_ground_revision.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v2','white-paths-v1'):gsub('street_city_ground_revision_payload.lua','street_city_white_paths_payload.lua')
assert(load(source,'white-paths-launcher'))()
