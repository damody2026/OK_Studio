return [====[
NIGHT_TAG='ResortMoonlight-v1'
NIGHT_DIR=ARCH+'/NightLighting'
MOON_LUX=6.0
MOON_BOUNCE_LUX=2.2
SKY_INTENSITY=1.5
MOON_DIAMETER_CM=19200.0

def detailed_moon_material(halo=False):
 name='M_MoonHalo_02' if halo else 'M_MoonSurface_02';path=NIGHT_DIR+'/'+name
 if EAL.does_asset_exist(path):return EAL.load_asset(path)
 m=ATS.create_asset(name,NIGHT_DIR,unreal.Material,unreal.MaterialFactoryNew());m.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_UNLIT)
 if halo:m.set_editor_property('blend_mode',unreal.BlendMode.BLEND_ADDITIVE)
 n=MEL.create_material_expression(m,unreal.MaterialExpressionPixelNormalWS);v=MEL.create_material_expression(m,unreal.MaterialExpressionCameraVectorWS)
 e=MEL.create_material_expression(m,unreal.MaterialExpressionCustom);inputs=[]
 for key in ['N','V']:
  i=unreal.CustomInput();i.set_editor_property('input_name',key);inputs.append(i)
 e.set_editor_property('inputs',inputs);e.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT3)
 code='''float facing=saturate(dot(normalize(N),normalize(V)));float r=sqrt(saturate(1-facing*facing));return float3(.30,.32,.38)*pow(saturate(1-r),2.6);''' if halo else '''
struct LunarNoise {
 float hash(float3 p){return frac(sin(dot(p,float3(127.1,311.7,74.7)))*43758.5453);}
 float value(float3 p){float3 i=floor(p),f=frac(p);f=f*f*(3-2*f);return lerp(lerp(lerp(hash(i),hash(i+float3(1,0,0)),f.x),lerp(hash(i+float3(0,1,0)),hash(i+float3(1,1,0)),f.x),f.y),lerp(lerp(hash(i+float3(0,0,1)),hash(i+float3(1,0,1)),f.x),lerp(hash(i+float3(0,1,1)),hash(i+float3(1,1,1)),f.x),f.y),f.z);}
};
LunarNoise noise;float3 p=normalize(N);float maria=noise.value(p*3.4+float3(7,2,9))*.68+noise.value(p*7.8+4)*.32;
float albedo=lerp(.36,.90,smoothstep(.30,.69,maria));
float2 uv=float2(p.x,p.z)*14;float2 cell=floor(uv);float relief=0;
[unroll]for(int y=-1;y<=1;y++){[unroll]for(int x=-1;x<=1;x++){
 float2 q=cell+float2(x,y);float h=noise.hash(float3(q,3));float2 center=q+float2(noise.hash(float3(q,1)),noise.hash(float3(q,2)));
 float radius=lerp(.12,.42,h);float d=length(uv-center)/radius;
 relief+=.16*exp(-pow((d-.93)*8,2))-.12*(1-smoothstep(.18,.90,d));
}}
albedo+=relief+(noise.value(p*72)-.5)*.09+(noise.value(p*145)-.5)*.035;
float facing=saturate(dot(p,normalize(V)));float limb=lerp(.62,1.0,pow(facing,.35));
float terminator=lerp(.72,1.04,saturate(dot(p,normalize(float3(-.5,-.8,.35)))*.5+.5));
return float3(1.0,.96,.88)*clamp(albedo,.20,1.05)*limb*terminator*1.45;
'''
 e.set_editor_property('code',code);assert MEL.connect_material_expressions(n,'',e,'N');assert MEL.connect_material_expressions(v,'',e,'V');assert MEL.connect_material_property(e,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 if halo:
  one=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);one.set_editor_property('r',1.);assert MEL.connect_material_property(one,'',unreal.MaterialProperty.MP_OPACITY)
 assert not MEL.recompile_material(m);EAL.set_metadata_tag(m,'MoonRevision','LunarSurface02:procedural maria,crater bowls,rims,fine regolith,soft limb');save_asset(m);return m

def ensure_night_sky():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 fill=actors.get('ResortMoonBounce') or night_actor(unreal.DirectionalLight,'ResortMoonBounce',[55000,55000,50000],unreal.Rotator(pitch=-65,yaw=145,roll=0))
 c=fill.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_light_color(unreal.LinearColor(.4,.55,.8,1));c.set_editor_property('cast_shadows',False)
 path=NIGHT_DIR+'/M_ResortNightSky'
 m=EAL.load_asset(path) if EAL.does_asset_exist(path) else None
 if not m:
  m=ATS.create_asset('M_ResortNightSky',NIGHT_DIR,unreal.Material,unreal.MaterialFactoryNew());m.set_editor_property('two_sided',True);m.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_UNLIT)
  n=MEL.create_material_expression(m,unreal.MaterialExpressionPixelNormalWS);e=MEL.create_material_expression(m,unreal.MaterialExpressionCustom);i=unreal.CustomInput();i.set_editor_property('input_name','N');e.set_editor_property('inputs',[i]);e.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT3);e.set_editor_property('code','float h=saturate(abs(N.z)); return lerp(float3(.10,.16,.27),float3(.015,.035,.09),h);');assert MEL.connect_material_expressions(n,'',e,'N');assert MEL.connect_material_property(e,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR);assert not MEL.recompile_material(m);save_asset(m)
 if 'ResortNightSky' not in actors:
  a=night_part('ResortNightSky','Sphere',[55000,55000,0],[600000,600000,600000],m);a.static_mesh_component.set_editor_property('cast_shadow',False)
 if 'ResortMoonDisc' not in actors:
  m=night_material('M_ResortMoonDisc',(.68,.79,1),0,1,4);a=night_part('ResortMoonDisc','Sphere',[165000,105000,150000],[3200,3200,3200],m);a.static_mesh_component.set_editor_property('cast_shadow',False)
  actors['ResortMoonDisc']=a
 moon=actors['ResortMoonDisc'];moon.modify();moon.static_mesh_component.modify();moon.set_actor_scale3d(unreal.Vector(*(MOON_DIAMETER_CM/100 for _ in range(3))));moon.static_mesh_component.set_material(0,detailed_moon_material())
 halo=actors.get('ResortMoonHalo') or night_part('ResortMoonHalo','Sphere',[165000,105000,150000],[MOON_DIAMETER_CM*1.6]*3,detailed_moon_material(True));halo.static_mesh_component.set_editor_property('cast_shadow',False)
 write('moon-disc-review',dict(status='prepared',revision='lunar-surface-v2',diameter_cm=MOON_DIAMETER_CM,diameter_multiplier=6,halo_diameter_cm=MOON_DIAMETER_CM*1.6,surface_material=moon.static_mesh_component.get_material(0).get_path_name(),note='Procedural lunar maria and crater relief shading;decorative moon enlarged without changing scene illumination.'))

def night_actor(cls,label,xyz,rotation=None):
 a=SUB.spawn_actor_from_class(cls,unreal.Vector(*xyz),rotation or unreal.Rotator())
 a.set_actor_label(label);a.set_folder_path('UniversityCity/ResortMoonlight');a.set_editor_property('tags',[NIGHT_TAG]);return a

def night_material(name,color,metal=0,rough=.5,emission=0):
 dest=NIGHT_DIR+'/'+name
 if EAL.does_asset_exist(dest):return EAL.load_asset(dest)
 m=ATS.create_asset(name,NIGHT_DIR,unreal.Material,unreal.MaterialFactoryNew())
 n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(*color,1))
 MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for value,prop in [(metal,unreal.MaterialProperty.MP_METALLIC),(rough,unreal.MaterialProperty.MP_ROUGHNESS)]:
  v=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);v.set_editor_property('r',value);MEL.connect_material_property(v,'',prop)
 if emission:
  e=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);e.set_editor_property('constant',unreal.LinearColor(*(v*emission for v in color),1));MEL.connect_material_property(e,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 assert not MEL.recompile_material(m);save_asset(m);return m

def night_part(label,shape,xyz,size,mat):
 a=night_actor(unreal.StaticMeshActor,label,xyz);c=a.static_mesh_component
 mesh=EAL.load_asset('/Engine/BasicShapes/'+shape+'.'+shape);assert mesh,shape
 c.set_static_mesh(mesh);c.set_material(0,mat);c.set_collision_profile_name('NoCollision');a.set_actor_scale3d(unreal.Vector(*(v/100 for v in size)));return a

def resort_night_environment(q):
 night=q.get('night',False)
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label()
  if label in ['ResortNightSky','ResortMoonDisc','ResortMoonHalo']:a.set_actor_hidden_in_game(not night);a.set_is_temporarily_hidden_in_editor(not night)
  if isinstance(a,unreal.SkyLight):a.light_component.set_intensity(SKY_INTENSITY if night else 2.5)
  elif isinstance(a,unreal.DirectionalLight):
   a.light_component.set_intensity((MOON_LUX if label=='ResortMoonlight' else (MOON_BOUNCE_LUX if label=='ResortMoonBounce' else 0.)) if night else (5. if label=='CitySun' else (1.8 if label=='CityStreetFill' else 0.)))
  elif NIGHT_TAG in [str(t) for t in a.tags] and isinstance(a,(unreal.SpotLight,unreal.PointLight)):a.light_component.set_visibility(night,False)

def install_night():
 old_scene_check()
 if any(NIGHT_TAG in [str(t) for t in a.tags] for a in SUB.get_all_level_actors()):
  receipt=jread(OUT/'moonlight-install.json');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};first={r['building_id']:r for r in jread(OUT/'baseline.json')['rows'] if r['floor']==1}
  backup=OUT/'backups'/('UniversityCity-before-moonlight-refine-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
  for row in receipt['rows']:
   if row['door_axis_clearance_cm']>=180:continue
   bid=row['id'];o=actors['RomanceName_'+bid].get_actor_bounds(False)[0];origin=first[bid]['xform']['location'];dx,dy=o.x-origin[0],o.y-origin[1];length=math.hypot(dx,dy);tx,ty=-dy/length,dx/length;offset=180-row['door_axis_clearance_cm']
   for name,a in actors.items():
    if not name.startswith('ResortLantern_'+bid+'_'):continue
    p=a.get_actor_location();sign=-1 if '_Bollard' in name else 1;a.modify();a.set_actor_location(unreal.Vector(p.x+tx*offset*sign,p.y+ty*offset*sign,p.z),False,False)
   for key,sign in [('lantern',1),('bollard',-1)]:row[key][0]+=tx*offset*sign;row[key][1]+=ty*offset*sign
   row['door_axis_clearance_cm']=180
  ensure_night_sky();resort_night_environment(dict(night=True));old_scene_check();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();receipt.update(map_sha256=sha(MAPFILE),refinement_backup=str(backup),moon_lux=MOON_LUX,sky_intensity=SKY_INTENSITY,moon_bounce_lux=MOON_BOUNCE_LUX);write('moonlight-install',receipt);return
 backup=OUT/'backups'/('UniversityCity-before-moonlight-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 bronze=night_material('M_LanternBronze',(.075,.055,.032),.75,.32)
 stone=night_material('M_LanternLimestone',(.53,.46,.34),0,.72)
 glow=night_material('M_LanternOpal',(.95,.62,.28),0,.35,3)
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};base=jread(OUT/'baseline.json');first={r['building_id']:r for r in base['rows'] if r['floor']==1};rows=[]
 for b in jread(OUT/'geometry-manifest.json')['buildings']:
  bid=b['id'];a=actors['RomanceName_'+bid];o,e=a.get_actor_bounds(False);f=first[bid];origin=f['xform']['location'];dx=o.x-origin[0];dy=o.y-origin[1];length=math.hypot(dx,dy);assert length>100
  nx,ny=dx/length,dy/length;tx,ty=-ny,nx;w=b['sign_board']['width_m']*100
  z=origin[2];h=370.;lateral=max(180.,min(w*.38,1050.))
  x,y=o.x+nx*220+tx*lateral,o.y+ny*220+ty*lateral
  prefix='ResortLantern_'+bid
  night_part(prefix+'_Plinth','Cylinder',[x,y,z+15],[42,42,30],stone)
  night_part(prefix+'_Foot','Cylinder',[x,y,z+37],[26,26,16],bronze)
  night_part(prefix+'_Stem','Cylinder',[x,y,z+180],[9,9,290],bronze)
  night_part(prefix+'_Tray','Cylinder',[x,y,z+333],[54,54,8],bronze)
  night_part(prefix+'_Opal','Cylinder',[x,y,z+353],[28,28,34],glow)
  night_part(prefix+'_Roof','Cone',[x,y,z+380],[72,72,26],bronze)
  for sx,sy in [(-1,-1),(-1,1),(1,-1),(1,1)]:night_part(prefix+'_Frame_'+str(sx)+'_'+str(sy),'Cube',[x+sx*19,y+sy*19,z+353],[3,3,38],bronze)
  light=night_actor(unreal.SpotLight,prefix+'_Light',[x,y,z+330],unreal.Rotator(pitch=-90,yaw=0,roll=0));c=light.light_component
  c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(2300);c.set_editor_property('attenuation_radius',1250.);c.set_editor_property('inner_cone_angle',42.);c.set_editor_property('outer_cone_angle',72.);c.set_editor_property('use_temperature',True);c.set_editor_property('temperature',2800.);c.set_editor_property('cast_shadows',False)
  # Opposite-side low bollard: discreet light at walking height, clear of entry axis.
  bx,by=o.x+nx*190-tx*lateral,o.y+ny*190-ty*lateral
  night_part(prefix+'_BollardFoot','Cylinder',[bx,by,z+12],[29,29,24],stone)
  night_part(prefix+'_BollardBody','Cylinder',[bx,by,z+46],[15,15,56],bronze)
  night_part(prefix+'_BollardOpal','Cylinder',[bx,by,z+78],[18,18,15],glow)
  night_part(prefix+'_BollardCap','Cylinder',[bx,by,z+89],[30,30,7],bronze)
  l=night_actor(unreal.PointLight,prefix+'_BollardLight',[bx,by,z+78]);lc=l.light_component;lc.set_mobility(unreal.ComponentMobility.MOVABLE);lc.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);lc.set_intensity(220);lc.set_editor_property('attenuation_radius',450.);lc.set_editor_property('use_temperature',True);lc.set_editor_property('temperature',2700.);lc.set_editor_property('cast_shadows',False)
  rows.append(dict(id=bid,lantern=[x,y,z],bollard=[bx,by,z],height_cm=h,door_axis_clearance_cm=lateral,lantern_lumens=2300,bollard_lumens=220))
 moon=night_actor(unreal.DirectionalLight,'ResortMoonlight',[55000,55000,50000],unreal.Rotator(pitch=-32,yaw=-38,roll=0));mc=moon.light_component;mc.set_mobility(unreal.ComponentMobility.MOVABLE);mc.set_light_color(unreal.LinearColor(.52,.65,1,1));mc.set_editor_property('cast_shadows',True);mc.set_editor_property('light_source_angle',2.)
 ensure_night_sky();resort_night_environment(dict(night=True));old_scene_check();assert sha(MAPFILE)==LOAD_SHA,'Concurrent write; do not overwrite'
 assert unreal.EditorLevelLibrary.save_current_level()
 write('moonlight-install',dict(status='passed',map_sha256=sha(MAPFILE),backup=str(backup),lanterns=122,bollards=122,moon_lux=MOON_LUX,sky_intensity=SKY_INTENSITY,rows=rows,original_scene_checks=old_scene_check(),note='Persistent art-directed night lighting; original actor transforms and mesh data preserved.'))
 write('install-night',dict(status='passed',map_sha256=sha(MAPFILE)))

def audit_night():
 audit_arch();data=jread(OUT/'moonlight-install.json');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};checks=0
 for r in data['rows']:
  for suffix,cls,lum in [('_Light',unreal.SpotLight,2300),('_BollardLight',unreal.PointLight,220)]:
   a=actors['ResortLantern_'+r['id']+suffix];assert isinstance(a,cls);assert abs(a.light_component.get_editor_property('intensity')-lum)<.01;checks+=2
   c=a.light_component;assert NIGHT_TAG in [str(t) for t in a.tags];assert c.get_editor_property('intensity_units')==unreal.LightUnits.LUMENS
   for prop,expected in [('attenuation_radius',1250 if lum==2300 else 450),('temperature',2800 if lum==2300 else 2700)]:assert abs(c.get_editor_property(prop)-expected)<.01;checks+=1
   assert not c.get_editor_property('cast_shadows');checks+=3
  assert r['door_axis_clearance_cm']>=180;checks+=1
  suffixes=['_Plinth','_Foot','_Stem','_Tray','_Opal','_Roof','_BollardFoot','_BollardBody','_BollardOpal','_BollardCap']+['_Frame_'+str(x)+'_'+str(y) for x,y in [(-1,-1),(-1,1),(1,-1),(1,1)]]
  for suffix in suffixes:
   a=actors['ResortLantern_'+r['id']+suffix];assert str(a.static_mesh_component.get_collision_profile_name())=='NoCollision';checks+=1
 assert abs(actors['ResortMoonlight'].light_component.get_editor_property('intensity')-MOON_LUX)<.001
 assert 'ResortNightSky' in actors and 'ResortMoonDisc' in actors and 'ResortMoonBounce' in actors
 assert len([a for a in actors.values() if NIGHT_TAG in [str(t) for t in a.tags]])==1957
 moon=actors['ResortMoonDisc'];assert abs(moon.get_actor_scale3d().x-MOON_DIAMETER_CM/100)<.001;assert moon.static_mesh_component.get_material(0).get_name()=='M_MoonSurface_02';assert 'ResortMoonHalo' in actors
 assert abs(actors['ResortMoonBounce'].light_component.get_editor_property('intensity')-MOON_BOUNCE_LUX)<.001
 write('moonlight-audit',dict(status='passed',checks=checks+9,lanterns=122,bollards=122,local_lights=244,tagged_actors=1957,moon_lux=MOON_LUX,moon_diameter_cm=MOON_DIAMETER_CM,moon_diameter_multiplier=6,map_sha256=sha(MAPFILE)))

def resort_night_views(views):
 result=[]
 for q in views:
  if q['name'] not in ['S01','S03','S09','H1','E1','R1','TR']:continue
  t=q['target'];d=[q['eye'][i]-t[i] for i in range(3)];length=math.hypot(d[0],d[1]);factor=min(2.2,1800/length);eye=[t[0]+d[0]*factor-d[1]*factor*.12,t[1]+d[1]*factor+d[0]*factor*.12,q['eye'][2]+80]
  result.append(dict(name=q['name']+'-moonlight',eye=eye,target=[t[0],t[1],t[2]-100],fov=86,night=True))
  if q['name'] in ['S03','H1']:result.append(dict(name=q['name']+'-skyline',eye=eye,target=[t[0],t[1],t[2]+900],fov=92,night=True))
 return result

original_run_arch=run_arch
def run_arch():
 try:
  if MODE=='install':
   install_night();write('install',dict(jread(OUT/'install.json'),map_sha256=sha(MAPFILE)));globals()['LOAD_SHA']=sha(MAPFILE);audit_night();render_arch()
  elif MODE=='audit':
   audit_night();assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');unreal.SystemLibrary.collect_garbage();schedule_arch_quit()
  elif MODE=='render':audit_night();render_arch()
  else:original_run_arch()
 except BaseException:
  write(MODE+'-error',dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc());unreal.SystemLibrary.quit_editor()
]====]
