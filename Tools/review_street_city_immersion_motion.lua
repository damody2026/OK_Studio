-- Derived QA sheets and animations; never alter native moving-capture pixels.
local run=assert(arg[1],'Pass runtime package run ID');assert(run:match('^package%-%d+%-%d+$'))
if arg[2]=='record' then
 package.path='Tools/lua/?.lua;'..package.path
 local j=require('ok.json');local h=require('ok.hash');local o='output/street-social-city-production/immersion-v1/'
 local path=o..'runtime-'..run..'-review/'
 local f=assert(io.open(path..'prepared.json','rb'));local r=j.decode(f:read('*a'));f:close()
 assert(tonumber(arg[3])==r.contact_sheets,'Review every motion sheet before recording')
 for _,v in ipairs(r.images)do assert(h.sha256_file(v.path)==v.sha256)end
 r.status='passed_reviewed_sampled_frames';r.observations=assert(arg[4]);r.reviewed_at=os.date('%Y-%m-%dT%H:%M:%S')..'+08:00'
 r.scope='All native frames sampled during three moving street-camera clips were reviewed in order. This is scoped temporal evidence, not full-map continuous video or a global no-z-fighting certificate.'
 f=assert(io.open(path..'visual-review.json','wb'));f:write(j.encode(r));f:close();print('Recorded moving-frame review '..run);return
end
local code=[====[
import json,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');run='__RUN__'
r=json.loads((O/('runtime-'+run+'.json')).read_text('utf8'));assert r['status']=='passed'
rows=r['native_motion_frames'];folder=O/('runtime-'+run+'-review');folder.mkdir(exist_ok=True)
manifest=[]
for v in rows:
 p=Path(v['image']);im=Image.open(p);assert im.size==(1920,1080)
 manifest.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),clip=v['clip'],elapsed_seconds=v['elapsed_seconds']))
for first in range(0,len(rows),8):
 group=rows[first:first+8];canvas=Image.new('RGB',(1280,380*((len(group)+1)//2)));draw=ImageDraw.Draw(canvas)
 for i,v in enumerate(group):
  im=Image.open(v['image']);im.thumbnail((640,360));x,y=i%2*640,i//2*380;canvas.paste(im,(x,y));draw.text((x+5,y+362),Path(v['image']).name,fill='white')
 canvas.save(folder/('motion-review-%02d.jpg'%(first//8+1)))
for clip in sorted(set(v['clip'] for v in rows)):
 group=[v for v in rows if v['clip']==clip];frames=[]
 for v in group:
  im=Image.open(v['image']).convert('RGB');im.thumbnail((960,540));frames.append(im)
 durations=[max(40,min(500,int((group[min(i+1,len(group)-1)]['elapsed_seconds']-v['elapsed_seconds'])*1000))) for i,v in enumerate(group)]
 frames[0].save(folder/('motion-%d.gif'%clip),save_all=True,append_images=frames[1:],duration=durations,loop=0)
(folder/'prepared.json').write_text(json.dumps(dict(status='prepared_requires_visual_review',source='runtime-'+run+'.json',original_images=len(rows),contact_sheets=(len(rows)+7)//8,images=manifest)),encoding='utf8')
print(folder,len(rows),'native moving frames')
]====]
code=code:gsub('__RUN__',run);local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
