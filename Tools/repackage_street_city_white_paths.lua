local f=assert(io.open('Tools/repackage_street_city_ground_revision.lua','rb'));local wrapper=f:read('*a');f:close()
local original=load
load=function(source,name)
 assert(name=='ground-revision-repackage')
 source=source:gsub('ground%-pbr%-v2','white-paths-v1')
 source=source:gsub("'StreetSocialCity/Content/UniversityCity/GroundPBRV2'","'StreetSocialCity/Content/UniversityCity/GroundPBRV2','StreetSocialCity/Content/UniversityCity/WhitePathsV1'")
 local needle="file:match('^StreetSocialCity/Content/UniversityCity/GroundPBRV[12]/')";local replacement="(file:match('^StreetSocialCity/Content/UniversityCity/GroundPBRV[12]/') or file:match('^StreetSocialCity/Content/UniversityCity/WhitePathsV1/'))";local n
 source,n=source:gsub(needle:gsub('(%W)','%%%1'),function()return replacement end);assert(n==1)
 return original(source,name)
end
assert(original(wrapper,'white-path-package-wrapper'))()
