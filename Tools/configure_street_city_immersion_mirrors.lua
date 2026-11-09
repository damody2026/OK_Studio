package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1'
local files={root..'/StreetSocialCity/Config/DefaultEngine.ini','E:/StreetSocialCityProduction/environment-packages/20261023-122745/HostProject/Config/DefaultEngine.ini','E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject/Config/DefaultEngine.ini'}
local rows={}
for i,p in ipairs(files)do
 local f=assert(io.open(p,'rb'));local old=f:read('*a');f:close();assert(not old:find('; Immersion large wall mirrors',1,true),'Already configured')
 local backup=out..'/mirror-renderer-before-'..i..'.ini';f=assert(io.open(backup,'wb'));f:write(old);f:close()
 local s=old..'\r\n; Immersion large wall mirrors: native planar reflections and SSR compatibility.\r\n[/Script/Engine.RendererSettings]\r\nr.AllowGlobalClipPlane=1\r\nr.ReflectionMethod=2\r\n';f=assert(io.open(p,'wb'));f:write(s);f:close();rows[#rows+1]={path=p,before_sha256=hash.sha256(old),sha256=hash.sha256(s),backup=backup}
end
local f=assert(io.open(out..'/mirror-renderer-config.json','wb'));f:write(json.encode({status='configured_requires_shader_compile_and_render',files=rows,reference='https://dev.epicgames.com/documentation/en-us/unreal-engine/planar-reflections-in-unreal-engine',settings={global_clip_plane=true,reflection_method='ScreenSpace plus native planar mirrors'},scope='Preserve global illumination and day/night settings. Native planar reflections require clip plane shaders; SSR avoids Lumen replacing the planar contribution.'}));f:close()
print('Configured native planar reflection support for source and both isolated E hosts')
