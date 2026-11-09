local code=[====[
from pathlib import Path
from PIL import Image
import json,hashlib,numpy as np
out=Path('output/street-social-city-production/resort-architecture-v1');review=json.loads((out/'relief-signs-review.json').read_text('utf8'));rows=[]
for r in review['rows']:
 paths={k:Path(p) for k,p in r['maps'].items()};color=np.asarray(Image.open(paths['color_height']));normal=np.asarray(Image.open(paths['normal_roughness']));height=np.asarray(Image.open(paths['height']))
 assert list(Image.open(paths['color_height']).size)==r['size']
 assert abs((r['layout_canvas_size'][0]/r['layout_canvas_size'][1])/(r['physical_size_m'][0]/r['physical_size_m'][1])-1)<.03,'Typesetting canvas distorts physical glyph aspect'
 assert color.shape==normal.shape and color.shape[2]==4 and np.array_equal(color[:,:,3],height)
 assert height.max()>=250 and height.min()<=30 and np.count_nonzero(height>240)>height.size*.002
 n=normal[:,:,:3].astype(np.float32)/255*2-1;length=np.linalg.norm(n,axis=2);assert np.max(abs(length-1))<.014
 assert normal[:,:,3].min()>=50 and normal[:,:,3].max()<=150
 rows.append(dict(building=r['building'],locale=r['locale'],style=r['style'],raised_fraction=float(np.mean(height>240)),height_range=[int(height.min()),int(height.max())],normal_unit_max_error=float(np.max(abs(length-1))),sha256={k:hashlib.sha256(p.read_bytes()).hexdigest() for k,p in paths.items()}))
assert len(rows)==366
(out/'relief-validation.json').write_text(json.dumps(dict(status='passed',translations=366,source_maps=1098,checks='Packed alpha matches grayscale height pixel-for-pixel;raised text coverage;unit tangent normals;roughness range;dimensions;SHA256 for every map',rows=rows),ensure_ascii=False,indent=2),'utf8')
print('Verified1098 maps /366 height fields and unit normals')
]====]
local process=assert(io.popen('python -','w'));assert(process:write(code));assert(process:close())
