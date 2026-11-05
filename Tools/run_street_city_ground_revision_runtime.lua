local f=assert(io.open('Tools/run_street_city_ground_runtime.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v1','ground-pbr-v2')
assert(load(source,'ground-revision-runtime'))()
