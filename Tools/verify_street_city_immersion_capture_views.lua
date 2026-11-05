-- Compare planned optical eyes with actual PlayerController camera output.
return function(v,text)
 local n='([%d%.%-]+)';local id=v.id:gsub('(%W)','%%%1')
 local x,y,z,p,yaw,roll,fov=text:match('CITY_IMMERSION_CAPTURE '..id..' eye='..n..','..n..','..n..' rot='..n..','..n..','..n..' fov='..n)
 assert(x,'Missing native player camera receipt: '..v.id)
 local eye={tonumber(x),tonumber(y),tonumber(z)}
 for i=1,3 do assert(math.abs(eye[i]-v.eye[i])<.2,'Native optical eye mismatch: '..v.id)end
 local dx,dy,dz=v.target[1]-v.eye[1],v.target[2]-v.eye[2],v.target[3]-v.eye[3]
 local ep=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)));local ey=math.deg(math.atan(dy,dx))
 local function angle(a,b)return math.abs((a-b+180)%360-180)end
 assert(angle(tonumber(p),ep)<.03 and angle(tonumber(yaw),ey)<.03 and angle(tonumber(roll),0)<.03,'Native camera rotation mismatch: '..v.id)
 assert(math.abs(tonumber(fov)-v.fov)<.03,'Native camera FOV mismatch: '..v.id)
 v.actual_camera_cm=eye;v.actual_camera_rotation_deg={tonumber(p),tonumber(yaw),tonumber(roll)};v.actual_camera_fov=tonumber(fov)
 local configured,active=text:match('CITY_IMMERSION_MIRRORS '..id..' configured=(%d+) active=(%d+)');assert(configured and tonumber(configured)==12 and tonumber(active)<=2,'Missing bounded native mirror activation receipt: '..v.id)
 if v.id:match('^mirror%-')then assert(tonumber(active)>=1,'No native planar mirror active at mirror inspection view: '..v.id)end
 v.configured_mirror_count=tonumber(configured);v.active_planar_mirrors=tonumber(active)
 local clip,method=text:match('CITY_IMMERSION_RENDERER clip=(%d+) reflections=(%d+)');assert(tonumber(clip)==1 and tonumber(method)==2,'Actual renderer has no supported planar mirror configuration')
 v.actual_clip_plane_enabled=true;v.actual_reflection_method=tonumber(method)
 local percent,rough=text:match('CITY_IMMERSION_MIRRORS '..id..' configured=%d+ active=%d+ capture_percent=(%d+) prefilter=([%d%.]+)')
 if percent then assert((tonumber(active)==0 and tonumber(percent)==0 or tonumber(percent)==75) and tonumber(rough)==0);v.mirror_capture_percent=tonumber(percent);v.mirror_prefilter_roughness=tonumber(rough)end
 v.capture_method='Native Game optical documentation pose:upright Pawn,77cm camera offset compensated,noclip only in explicit capture process. Actual supported CharacterMovement verified separately.'
end
