local f=assert(io.open('Tools/repackage_street_city_white_paths.lua','rb'));local wrapper=f:read('*a');f:close()
local original=load
load=function(source,name)
 if name=='ground-revision-repackage' then
  source=source:gsub('white%-paths%-v1','pk0102-floor-v1')
  local needle="local target='E:/StreetSocialCityProduction/environment-packages/'..id";local n
  source,n=source:gsub(needle:gsub('(%W)','%%%1'),"local target=ground..'/packages/'..id");assert(n==1)
  needle="[IO.DriveInfo]::new('E')";source,n=source:gsub(needle:gsub('(%W)','%%%1'),"[IO.DriveInfo]::new('C')");assert(n==1)
 end
 return original(source,name)
end
assert(original(wrapper,'pk0102-package-wrapper'))()
