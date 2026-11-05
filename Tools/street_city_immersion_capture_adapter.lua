-- Place optical eye independently of Pawn pitch; verify actual native camera.
return function(source)
 local count
 source,count=source:gsub('BugItGo %%%.6f %%%.6f %%%.6f %%%.6f %%%.6f 0',function()return 'CityImmersionCapturePose %.6f %.6f %.6f %.6f %.6f'end,1);assert(count==1,'Optical capture-pose adapter failed')
 source,count=source:gsub('BugItGo to:','CITY_IMMERSION_CAPTURE_POSE',1);assert(count==1,'Optical pose receipt guard adapter failed')
 source,count=source:gsub("defer%(98,'LogLoc'%)","defer(98,'CityImmersionViewPoint '..v.id)",1);assert(count==1,'Native optical camera logger adapter failed')
 source,count=source:gsub("'%-nosplash'","'-nosplash','-CityImmersionCapture'",1);assert(count==1,'Opt-in capture flag adapter failed')
 source,count=source:gsub('for _,v in ipairs%(views%)do local f=',"local verify_view=dofile('Tools/verify_street_city_immersion_capture_views.lua');for _,v in ipairs(views)do verify_view(v,text);local f=",1);assert(count==1,'Native optical camera validation adapter failed')
 assert(load(source,'native-optical-capture-adapted'))
 return source
end
