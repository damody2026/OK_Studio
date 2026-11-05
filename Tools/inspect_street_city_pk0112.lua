local code=[====[
import json,struct,numpy as np
from pathlib import Path
from PIL import Image,ImageDraw
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/flat-campus-v1');S=O.parent/'day-night-v1/surface-final'
def read(p):return json.loads(p.read_text(encoding='utf8'))
s=read(S/'scene.json');r=next(r for r in s['instances'] if r['actor']=='World_PK_0112');a=s['meshes'][r['mesh']];l=a['lods'][0];raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);idx=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);sl=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);live=next(q for q in read(O/'preservation.json')['after'] if q['actor']==r['actor']);mat=np.array(r['matrix']).reshape(4,4);mat[3,:3]=live['transform']['translation'];p=read(O/'PK0112-grade-plan.json');xyz=np.frombuffer(Path(p['meshes'][0]['lods'][0]['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3)[:,1];w=np.c_[xyz,np.ones(nv)]@mat;t=w[idx,:3];n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);area=np.linalg.norm(n,axis=1)/2;top=np.isin(sl,[1,5])&(np.abs(t[:,:,2]-1202).max(1)<.05)&(area>1);polys=t[top,:,:2];lo=polys.reshape(-1,2).min(0);hi=polys.reshape(-1,2).max(0);im=Image.new('RGB',(1300,1000),'white');d=ImageDraw.Draw(im);scale=min(1200/(hi[0]-lo[0]),900/(hi[1]-lo[1]))
def pix(q):return (50+(q[0]-lo[0])*scale,950-(q[1]-lo[1])*scale)
for poly in polys:d.polygon([pix(v) for v in poly],fill='#dddddd',outline='#222222')
for x in range(int(lo[0]//1000)*1000,int(hi[0])+1000,1000):
 xx=pix([x,lo[1]])[0];d.line((xx,30,xx,960),fill='#88bbbb');d.text((xx,970),str(x),fill='black')
for y in range(int(lo[1]//1000)*1000,int(hi[1])+1000,1000):
 yy=pix([lo[0],y])[1];d.line((30,yy,1270,yy),fill='#88bbbb');d.text((0,yy),str(y),fill='black')
im.save(O/'PK0112-paving-plan.png');print('XY bounds',lo.tolist(),hi.tolist())
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
