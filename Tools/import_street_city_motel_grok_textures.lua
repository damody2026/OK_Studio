-- Copy Grok-generated art (grok-media/*.jpg) into the motel texture folder as power-of-two PNGs named grok_<key>.png,
-- so room specs can reference them with {"tex":"grok_<key>","fit":true}. The key -> source map is
-- motel-v1/sample-rooms/grok-textures.json ({"<key>": {"src": "<path>", "prompt": "..."}}); existing PNGs are rebuilt.
local code=[====[
import json
from pathlib import Path
from PIL import Image
S=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1/sample-rooms');T=S/'textures'
m=json.loads((S/'grok-textures.json').read_text('utf8'))
def pot(n):
 p=256
 while p*2<=n*1.25 and p<2048:p*=2
 return p
for k,v in m.items():
 im=Image.open(v['src']).convert('RGB');w,h=pot(im.width),pot(im.height)
 im.resize((w,h),Image.LANCZOS).save(T/('grok_'+k+'.png'));print('grok_'+k,w,h)
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write(code));assert(p:close())
