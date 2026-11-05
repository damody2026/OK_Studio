return [====[
def sign_night_profile(style):
 mode,strength={'ivory_lightbox':(1,2.2),'cream_bronze':(1,1.7),'navy_channel':(0,3.2),'sage_ceramic':(0,2.5),'burgundy_enamel':(0,2.8),'charcoal_brass':(2,3.0),'walnut_brass':(2,2.6)}[style]
 return dict(mode=mode,strength=strength,night_factor=1.0,version='night-01',method=['lit_letters','lit_background','backlit_halo'][mode])

def name_material(bid,existing,vertical=False):
 review=jread(OUT/'relief-signs-review.json');design=next(q for q in review['designs'] if q['id']==bid)
 rows=[q for q in review['rows'] if q['building']==bid];assert len(rows)==3
 code_version='relief-pom-v3-physical-04'
 digest=hashlib.sha256((json.dumps(design,sort_keys=True)+code_version).encode()+b''.join((ROOT/q['maps'][kind]).read_bytes() for q in rows for kind in ['color_height','normal_roughness'])).hexdigest()[:16]
 profile=sign_night_profile(design['style']);night_digest=hashlib.sha256((digest+json.dumps(profile,sort_keys=True)).encode()).hexdigest()[:16]
 name='MI_Night_'+bid+'_'+night_digest;folder=ARCH+'/SignsReliefV3';dest=folder+'/'+name
 cached=EAL.load_asset(dest) if EAL.does_asset_exist(dest) else None
 expected_settings=dict(mip_gen_settings=unreal.TextureMipGenSettings.TMGS_NO_MIPMAPS,never_stream=True,lod_bias=0,compression_settings=unreal.TextureCompressionSettings.TC_EDITOR_ICON)
 if cached:
  valid=True
  if cached.get_editor_property('parent').get_name()!='M_ReliefShared_Night_01':valid=False
  for label,v in [('SignLightMode',profile['mode']),('SignNightStrength',1.0),('SignGlowStrength',profile['strength'])]:
   if abs(MEL.get_material_instance_scalar_parameter_value(cached,label)-v)>.00001:valid=False
  for locale in ['zh_Hant','zh_Hans','en']:
   for prefix in ['CityText_','SignDetail_']:
    t=MEL.get_material_instance_texture_parameter_value(cached,prefix+locale)
    if not t or any(t.get_editor_property(k)!=v for k,v in expected_settings.items()) or t.get_editor_property('srgb')!=(prefix=='CityText_'):valid=False
  if valid:return cached
 parent_name='M_ReliefShared_Night_01';parent_path=folder+'/'+parent_name
 shared=EAL.does_asset_exist(parent_path)
 m=EAL.load_asset(parent_path) if shared else ATS.create_asset(parent_name,folder,unreal.Material,unreal.MaterialFactoryNew())
 m.set_editor_property('two_sided',True)
 def exp(cls,x=0,y=0):return MEL.create_material_expression(m,cls,x,y)
 def wire(a,b,pin,out=''):assert MEL.connect_material_expressions(a,out,b,pin),(str(a.get_class().get_name()),str(b.get_class().get_name()),pin,out)
 def value(v):
  n=exp(unreal.MaterialExpressionConstant);n.set_editor_property('r',float(v));return n
 def shader(inputs,code,kind=unreal.CustomMaterialOutputType.CMOT_FLOAT3):
  n=exp(unreal.MaterialExpressionCustom);defs=[]
  for label,src in inputs:
   q=unreal.CustomInput();q.set_editor_property('input_name',label);defs.append(q)
  n.set_editor_property('inputs',defs);n.set_editor_property('code',code);n.set_editor_property('output_type',kind)
  for label,src in inputs:wire(src,n,label)
  return n
 def channels(src,flags):
  n=exp(unreal.MaterialExpressionComponentMask)
  for k,v in zip(['r','g','b','a'],flags):n.set_editor_property(k,v)
  wire(src,n,'');return n
 textures=[];bindings={}
 def parameter(label,default):
  n=exp(unreal.MaterialExpressionScalarParameter);n.set_editor_property('parameter_name',label);n.set_editor_property('default_value',float(default));return n
 def instance():
  mi=cached or ATS.create_asset(name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,m)
  for label,t in bindings.items():MEL.set_material_instance_texture_parameter_value(mi,label,t)
  for label,v in [('SignDepthU',2.8/(design['physical_size_m'][0]*100)),('SignDepthV',2.8/(design['physical_size_m'][1]*100)),('SignMetallic',design['letter_metallic']),('SignEmission',design['emission'])]:MEL.set_material_instance_scalar_parameter_value(mi,label,float(v))
  for label,v in [('SignLightMode',profile['mode']),('SignNightStrength',profile['night_factor']),('SignGlowStrength',profile['strength'])]:MEL.set_material_instance_scalar_parameter_value(mi,label,float(v))
  for key,val in [('CityTextID','building.'+bid),('SignArtwork','large text only'),('SignRelief','POM-2.8cm'),('SignFinish',design['style']),('SignSourceSHA256',digest)]:EAL.set_metadata_tag(mi,key,val)
  EAL.set_metadata_tag(mi,'SignNightLighting',profile['method'])
  save_asset(mi);return mi
 for i,row in enumerate(rows):
  locale=row['locale'];objects=[]
  for kind in ['color_height','normal_roughness']:
   texture_name='T_Relief_'+bid+'_'+digest+'_'+locale.replace('-','_')+'_'+kind;texture_path=folder+'/'+texture_name
   if EAL.does_asset_exist(texture_path):t=EAL.load_asset(texture_path)
   else:
    task=unreal.AssetImportTask();task.filename=str(ROOT/row['maps'][kind]);task.destination_path=folder;task.destination_name=texture_name;task.automated=True;task.save=True;ATS.import_asset_tasks([task]);t=EAL.load_asset(task.imported_object_paths[0]);assert t
   changed=False
   for key,v in dict(expected_settings,srgb=kind=='color_height').items():
    if t.get_editor_property(key)!=v:t.modify();t.set_editor_property(key,v);changed=True
   if changed:save_asset(t)
   assert [t.blueprint_get_size_x(),t.blueprint_get_size_y()]==row['size'],(bid,locale,kind,'texture dimensions')
   label=('CityText_' if kind=='color_height' else 'SignDetail_')+locale.replace('-','_');bindings[label]=t
   if not shared:
    n=exp(unreal.MaterialExpressionTextureObjectParameter,-1600,i*300);n.set_editor_property('parameter_name',label);n.set_editor_property('texture',t);n.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_COLOR if kind=='color_height' else unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR);objects.append(n)
  textures.append(objects)
 if shared:return instance()
 col=EAL.load_asset('/Game/UniversityCity/Localization/MPC_CityLanguage');lang=exp(unreal.MaterialExpressionCollectionParameter);lang.set_editor_property('collection',col);lang.set_editor_property('parameter_name','LanguageIndex')
 uv=exp(unreal.MaterialExpressionTextureCoordinate);view=exp(unreal.MaterialExpressionCameraVectorWS);ts=exp(unreal.MaterialExpressionTransform);ts.set_editor_property('transform_source_type',unreal.MaterialVectorCoordTransformSource.TRANSFORMSOURCE_WORLD);ts.set_editor_property('transform_type',unreal.MaterialVectorCoordTransform.TRANSFORM_TANGENT);wire(view,ts,'')
 bases=[('C'+str(i),t[0]) for i,t in enumerate(textures)];details=[('N'+str(i),t[1]) for i,t in enumerate(textures)]
 sample_h='if(Lang<0.5) h=Texture2DSampleLevel(C0,C0Sampler,saturate(q),0).a; else if(Lang<1.5) h=Texture2DSampleLevel(C1,C1Sampler,saturate(q),0).a; else h=Texture2DSampleLevel(C2,C2Sampler,saturate(q),0).a;'
 pom_code='float3 v=normalize(V);float2 ray=-v.xy/max(abs(v.z),0.18)*float2(RX,RY);float low=0,high=1,d=0,h=1;float2 q=UV;[loop] for(int i=0;i<32;i++){d=(i+1)/32.0;q=UV+ray*d;'+sample_h+'if(d>=1-h){low=max(0,d-1.0/32.0);high=d;break;}}[unroll] for(int j=0;j<5;j++){d=(low+high)*0.5;q=UV+ray*d;'+sample_h+'if(d>=1-h)high=d;else low=d;}d=(low+high)*0.5;return float3(saturate(UV+ray*d),d);'
 pom=shader(bases+[('Lang',lang),('UV',uv),('V',ts),('RX',parameter('SignDepthU',.003)),('RY',parameter('SignDepthV',.035))],pom_code);pom.set_editor_property('desc','32-step parallax occlusion mapping;2.8cm raised letters/recessed backing')
 color=shader(bases+[('Lang',lang),('P',pom)],'if(Lang<0.5)return Texture2DSampleLevel(C0,C0Sampler,P.xy,0).rgb;else if(Lang<1.5)return Texture2DSampleLevel(C1,C1Sampler,P.xy,0).rgb;return Texture2DSampleLevel(C2,C2Sampler,P.xy,0).rgb;')
 detail=shader(details+[('Lang',lang),('P',pom)],'float4 t;if(Lang<0.5)t=Texture2DSampleLevel(N0,N0Sampler,P.xy,0);else if(Lang<1.5)t=Texture2DSampleLevel(N1,N1Sampler,P.xy,0);else t=Texture2DSampleLevel(N2,N2Sampler,P.xy,0);return float4(normalize(t.rgb*2-1),t.a);',unreal.CustomMaterialOutputType.CMOT_FLOAT4)
 normal=channels(detail,[True,True,True,False]);roughness=channels(detail,[False,False,False,True])
 depth=shader([('P',pom),('V',ts)],'return P.z*2.8/max(abs(normalize(V).z),0.18);',unreal.CustomMaterialOutputType.CMOT_FLOAT1)
 metallic=shader([('P',pom),('Metal',parameter('SignMetallic',.5))],'return Metal*saturate((0.65-P.z)*3);',unreal.CustomMaterialOutputType.CMOT_FLOAT1)
 glow_code='''float letters=1-smoothstep(0.15,0.38,P.z);float panel=smoothstep(0.72,0.85,P.z);
float3 warm=float3(1.0,0.77,0.48);float3 hue=C/max(max(max(C.r,C.g),C.b),0.04);
if(Mode<0.5)return lerp(hue,float3(1,0.88,0.69),0.55)*Glow*Night*letters;
if(Mode<1.5)return lerp(C,float3(1,0.87,0.70),0.3)*Glow*Night*panel;
float halo=0;float2 stepUV=float2(RX,RY)*0.85;
[unroll]for(int k=0;k<8;k++){float a=k*0.78539816;float2 q=saturate(P.xy+float2(cos(a),sin(a))*stepUV);float h;
'''+sample_h+'''halo+=smoothstep(0.72,0.92,h)/8.0;}
return (warm*halo*panel*3.5+C*letters*0.07)*Glow*Night;'''
 emission=shader(bases+[('Lang',lang),('P',pom),('C',color),('RX',parameter('SignDepthU',.003)),('RY',parameter('SignDepthV',.035)),('Glow',parameter('SignGlowStrength',2.5)),('Night',parameter('SignNightStrength',1)),('Mode',parameter('SignLightMode',0))],glow_code)
 # Material attributes expose PDO as a normal input, avoiding the hidden native
 # MaterialProperty enum member in the Python wrapper.
 attributes=exp(unreal.MaterialExpressionMakeMaterialAttributes);m.set_editor_property('use_material_attributes',True)
 pins={str(p).replace(' ','').lower():str(p) for p in MEL.get_material_expression_input_names(attributes)}
 for n,pin in [(color,'basecolor'),(normal,'normal'),(roughness,'roughness'),(metallic,'metallic'),(depth,'pixeldepthoffset'),(emission,'emissivecolor')]:
  assert pin in pins,(pin,pins);wire(n,attributes,pins[pin])
 assert MEL.connect_material_property(attributes,'',unreal.MaterialProperty.MP_MATERIAL_ATTRIBUTES)
 errors=MEL.recompile_material(m);assert not errors,(bid,errors)
 EAL.set_metadata_tag(m,'SignRelief','POM-2.8cm');save_asset(m);return instance()

def write_night_signs_review(rows):
 records=[];counts=dict(lit_letters=0,lit_background=0,backlit_halo=0)
 for row in rows:
  mat=EAL.load_asset(row['sign_material']);method=EAL.get_metadata_tag(mat,'SignNightLighting');assert method in counts
  strength=MEL.get_material_instance_scalar_parameter_value(mat,'SignGlowStrength');factor=MEL.get_material_instance_scalar_parameter_value(mat,'SignNightStrength');assert strength>0 and factor==1
  counts[method]+=1;records.append(dict(id=row['id'],material=mat.get_path_name(),style=EAL.get_metadata_tag(mat,'SignFinish'),method=method,strength=strength,enabled=factor))
 assert len(records)==122
 write('night-signs-review',dict(status='passed',buildings=122,counts=counts,rows=records,activation='Emissive enabled by default;SignNightStrength supports dimming or switching in a material instance. Existing city has no time-of-day controller.',texture_sources='Existing trilingual color-height masks and physical relief reused;no lettering distortion or new logo artwork.'))
]====]
