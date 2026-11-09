local f=assert(io.open('Tools/street_city_ground_revision.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v2','flat-campus-v1'):gsub('street_city_ground_revision_payload.lua','street_city_flat_campus_payload.lua')
source=source:gsub('revision_audit=true','revision_audit=true,flat_inventory=true,flat_install=true,flat_audit=true,flat_finalize=true,flat_rebuild_enclosure=true,flat_name_polish=true,flat_grade=true,flat_annex=true,flat_site_polish=true,flat_site_grade=true')
assert(load(source,'flat-campus-launcher'))()
