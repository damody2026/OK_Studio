local f=assert(io.open('Tools/street_city_flat_campus.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('flat%-campus%-v1','traffic-v1'):gsub('street_city_flat_campus_payload.lua','street_city_traffic_payload.lua')
source=source:gsub('flat_inventory=true','flat_inventory=true,traffic_sign_finish=true,traffic_signal_brightness=true')
assert(load(source,'traffic-launcher'))()
