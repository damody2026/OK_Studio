local f=assert(io.open('Tools/street_city_ground_revision.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v2','pk0102-floor-v1'):gsub('street_city_ground_revision_payload.lua','street_city_pk0102_floor_payload.lua')
assert(load(source,'pk0102-floor-launcher'))()
