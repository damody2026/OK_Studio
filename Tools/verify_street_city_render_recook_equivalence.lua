-- Read-only comparison of serialized map and every referenced static-mesh chunk.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json')
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1'
local f=assert(io.open('output/street-social-city-production/day-night-v1/package.json','rb'));local p=j.decode(f:read('*a'));f:close();assert(p.exit_code==0 and p.id~='20261024-135124')
local r=ok.proc.run({'rg','--files','-uuu',p.target..'/Stage/Windows/StreetSocialCity/Content/Paks'},{capture=true,hide=true});assert(r.code==0);local pak=r.stdout:match('([^\r\n]+%.pak)');assert(pak)
local listing=o..'/pak-list-'..p.id..'.txt';r=ok.proc.run({'E:/PhysX/UE5.8/Engine/Binaries/Win64/UnrealPak.exe',pak,'-List'},{hide=true,stdout_file=listing,stderr_file=listing..'.stderr',timeout=120});assert(r.code==0)
local code=[====[
import json,re,hashlib
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu');O=R/'output/street-social-city-production/immersion-v1'
def read(p):return json.loads(p.read_text('utf-8-sig'))
def listing(p):return {n:h.lower() for n,h in re.findall(r'"([^"]+)" offset: .*?sha1: ([A-Fa-f0-9]{40}),',p.read_text('utf-8-sig'))}
old=read(O/'checkpoint-20261024-135124/package.json');new=read(R/'output/street-social-city-production/day-night-v1/package.json')
assert old['map_sha256']==new['map_sha256'] and old['prebuilt_game_sha256']==new['prebuilt_game_sha256'] and old['source_config_sha256']==new['source_config_sha256'] and old['source_game_config_sha256']==new['source_game_config_sha256']
a=listing(O/'checkpoint-20261024-135124/pak-list.txt');b=listing(O/('pak-list-'+new['id']+'.txt'));assert len(a)>1000 and len(b)>1000
stems={'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity'};editor_previews=set()
snapshot=read(O/'preservation-after.json');assert snapshot['map_sha256']==new['map_sha256']
for c in snapshot['components']:
 m=c.get('mesh','').split('.')[0]
 if m=='/Engine/EditorMeshes/PlanarReflectionPlane':editor_previews.add(m);continue
 if m.startswith('/Game/'):stems.add('StreetSocialCity/Content/'+m[6:])
 elif m.startswith('/Engine/'):stems.add('Engine/Content/'+m[8:])
checks=[];missing=[];different=[]
for stem in sorted(stems):
 chunks=[n for n in a if n.rsplit('.',1)[0]==stem]
 if not chunks:missing.append(stem);continue
 for n in chunks:
  checks.append(n)
  if a[n]!=b.get(n):different.append(dict(path=n,before=a[n],after=b.get(n)))
report=dict(status='passed' if not missing and not different else 'failed',before_package=old['id'],after_package=new['id'],map_sha256=new['map_sha256'],game_sha256=new['prebuilt_game_sha256'],referenced_mesh_and_map_packages=len(stems),serialized_chunks_checked=len(checks),excluded_editor_only_preview_packages=sorted(editor_previews),missing=missing,different=different,scope='Exact UnrealPak SHA-1 equality for current map and every referenced runtime static-mesh package chunk, plus identical source-map, executable and config SHA-256. Hidden PlanarReflectionPlane editor preview is stripped from both cooked packages. Renderer/material shaders are separately replayed; earlier walking results retain their original package identity.')
(O/'render-recook-equivalence.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8');assert report['status']=='passed',str(report)[:1500];print('Serialized geometry unchanged:',len(checks),'chunks')
]====]
local pipe=assert(io.popen('python -','w'));assert(pipe:write(code));assert(pipe:close())
