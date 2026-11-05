-- Fidelity pass 4 for the 57 mass-production motel rooms (c-motel-rooms review, 2026-10-28): per-room spec edits that
-- use the new procedural pieces of build_street_city_motel_rooms_v2.lua (trellis, padded_wall, filigree_screen,
-- pipe_arches, crystal_spiral, bubble_pendant, drip_frieze, ceiling_neon, film_strip, gazebo, hanging_chair, ceiling
-- ovals, sky gen). Room-independent upgrades (rect tub deck, tied canopies, deep drapes, 3D tufted / lattice walls,
-- deep red-brown marble, camera nudge) live in the builder itself. Idempotent: always starts from the first-run
-- backup room-specs/batch-NN.before-fidelity-v4.json.
-- Usage: lua Tools/apply_street_city_motel_fidelity_v4.lua [--dry]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json')
local dir='output/street-social-city-production/motel-v1/room-specs/'
local dry=arg[1]=='--dry'
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local r=f:read('*a');f:close();return r end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local function arr(t)return j.array(t)end
local function wall(x,side,pred)for _,w in ipairs(x.walls or {})do if w.side==side and (not pred or pred(w))then return w end end end
local function drop(list,pred)local out=arr({});for _,e in ipairs(list or {})do if not pred(e)then out[#out+1]=e end end;return out end
local function add(x,e)x.extras=x.extras or arr({});x.extras[#x.extras+1]=e end
local GOLD={color={0.85,0.65,0.25},rough=0.3,metal=0.85}
local P={}
-- 212 阿拉伯皇宮: gold diamond trellis over black upholstery behind the bed
P['imore-6f5e5a7cdf7b']=function(x)
 local w=wall(x,'rear');w.mat={gen={kind='tufted',bg={0.03,0.03,0.04},fg={0.07,0.06,0.07},line={0.01,0.01,0.01}},tile=0.6,rough=0.5}
 add(x,{type='trellis',side='rear',range={-7.0,0.0},z={0.4,3.3},back='none',off=0.16,pitch=0.6,bar=GOLD})
end
-- 213 埃及艷色: gold pierced filigree screen behind the bed (backlit) and the red tube arches
P['imore-345b250913f7']=function(x)
 local w=wall(x,'rear');w.mat={color={0.03,0.03,0.04},rough=0.3}
 -- explicit mat: build_street_city_motel_room_textures.lua only generates gen textures named in the specs
 add(x,{type='filigree_screen',side='rear',range={-5.6,-1.1},z={0.85,3.45},glow={1.0,0.72,0.38},emit=2.5,mat={gen={kind='filigree',bg={0.03,0.02,0.01},fg={0.85,0.65,0.25},cell=256},tile=0.9,metal=0.6,rough=0.3}})
 add(x,{type='pipe_arches',at={-3.34,4.7},w=3.0,h=3.1})
end
-- S18 201 夏威夷: black/white diamond upholstery with a gold trellis over it; crystal spiral instead of fibre strands
P['imore-6f34e45428fb']=function(x)
 local w=wall(x,'rear',function(w)return w.mat.gen and w.mat.gen.kind=='check' end);if w then w.mat={color={0.04,0.04,0.05},rough=0.4} end
 add(x,{type='padded_wall',side='rear',range={-5.0,-1.7},z={0.35,2.15},pattern='diamond',size=0.38,mats={{color={0.93,0.92,0.9},rough=0.55},{color={0.05,0.05,0.06},rough=0.5}},button=GOLD})
 add(x,{type='trellis',side='rear',range={-5.0,-1.7},z={0.35,2.15},back='none',off=0.16,pitch=0.54,bar=GOLD})
 x.extras=drop(x.extras,function(e)return e.type=='fiber_curtain' end)
 add(x,{type='crystal_spiral',at={-3.34,2.75},r=0.5,drop=1.9,n=90})
 add(x,{type='crystal_spiral',at={-0.4,4.6},r=0.25,drop=1.7,n=40})
end
-- 307 花之物語: bubble pendant cluster over the living dome
P['imore-da6f2b8100be']=function(x)
 add(x,{type='bubble_pendant',at={2.3,-0.6},n=11,glow={1.0,0.7,0.85},emit=4.0})
end
-- 214 華納威秀: painted sky ceiling, film-strip band
P['imore-50e4f52e8ae8']=function(x)
 local sky={gen={kind='sky',top={0.22,0.48,0.9},bottom={0.62,0.8,0.98}},fit=true,emit=1.2,rough=0.8}
 x.ceiling.field=sky;x.ceiling.dome_field=sky
 add(x,{type='film_strip',side='left',range={-3.0,1.5},posters=arr({})})
end
-- 312 Candy House: blue wave neon under the ceiling, icing drips over the brown cornice band
P['wego-linsen-c3b9042e0d82']=function(x)
 add(x,{type='ceiling_neon',color={0.2,0.55,1.0},amp=0.25,waves=0.6})
 add(x,{type='drip_frieze',side='left',range={-3.0,6.2},z=3.05})
 add(x,{type='drip_frieze',side='right',range={-4.4,6.2},z=3.05})
 add(x,{type='drip_frieze',side='rear',range={-7.0,0.0},z=3.05})
end
-- 315 / 402 第五大道: gold-mosaic oval recess instead of the round dome
for _,id in ipairs({'wego-linsen-2782e2e0c891','wego-linsen-97abd5a058ae'})do
 P[id]=function(x)local c=x.ceiling;c.ovals={{at={-1.0,1.4},r={2.6,1.7},mat=c.dome_field}};c.domes=arr({}) end
end
-- 304 普羅旺斯: the purple armchair stood on the bed axis 2 m in front of the foot and filled the bed-front view;
-- angle it beside the bed instead
P['imore-f06fdb6a278a']=function(x)
 for _,s in ipairs(x.living.seats)do if s.kind=='baroque_chair' then s.at={-5.5,3.1};s.rot=60 end end
end
-- 405 戀戀瑪姬: lavender upholstered panel grid behind the bed
P['wego-linsen-3480fecda6b2']=function(x)
 add(x,{type='padded_wall',side='rear',range={-6.0,-0.7},z={0.5,3.2},pattern='rect',size=0.5,mats={{color={0.8,0.68,0.85},rough=0.6},{color={0.86,0.76,0.9},rough=0.6}},frame='gold'})
end
-- 205 pool suite 3: real thatched pavilion and a hanging rattan chair on the raised decks (were boxes)
P['imore-8ed9ae8ccd08']=function(x)
 local pl=x.pool;pl.extras=drop(pl.extras,function(e)return e.name=='Thatch hut roof' or e.name=='Hut post' or e.name=='Rattan egg chair' end)
 pl.extras[#pl.extras+1]={type='gazebo',at={-13.6,8.6},size=1.9,z=1.36,h=1.75,layers=4}
 pl.extras[#pl.extras+1]={type='hanging_chair',at={-13.7,2.0},z=1.36}
 pl.water={color={0.03,0.15,0.13},opacity=0.85}
end
-- 207 pool suite 2: green-blue water over the curved-stripe mosaic (photo), not the shared bright cyan spa water
P['imore-491f7709b202']=function(x)
 x.pool=x.pool or {};x.pool.water={color={0.03,0.16,0.15},opacity=0.85}
end
-- 201 pool suite 5: dark navy pool mosaic (photo), not the default bright blue
P['imore-281de587d726']=function(x)
 x.pool=x.pool or {};x.pool.pool_wall='mosaic_navy'
 x.pool.water={color={0.01,0.025,0.07},opacity=0.9}
 x.pool.pool_floor={gen={kind='mosaic',colors={{0.05,0.07,0.2},{0.03,0.04,0.12},{0.1,0.12,0.3}},tiles=64,grout={0.02,0.02,0.05}},tile=1.0,rough=0.15}
end
local P5={}
-- ===== pass 5 (2026-10-28): official-photo review of 403-416, 501-514 and the 311 entry arcade; applied after pass 4
-- 403 66號公路: cream lit tray ceiling (was dark grey), dark-brown leather headboard + caramel chesterfield (read beige/tan), plain black granite tub deck instead of loud white-vein marble
P5['wego-linsen-6b8004633136']=function(x)
 if x.ceiling then
  x.ceiling.field={color={0.88,0.8,0.62},rough=0.8,emit=0.35}
  x.ceiling.soffit={color={0.9,0.84,0.7},rough=0.7}
 end
 if x.bed and x.bed.headboard then
  x.bed.headboard.mat={color={0.12,0.07,0.04},rough=0.35}
  x.bed.headboard.button={color={0.05,0.03,0.02},rough=0.4}
 end
 if x.living and x.living.seats then
  for _,s in ipairs(x.living.seats)do if s.kind=='chesterfield' then s.mat={color={0.36,0.18,0.07},rough=0.35} end end
 end
 if x.bath then x.bath.surround={color={0.03,0.03,0.03},rough=0.12} end
end
-- 404 威尼斯音樂盒: deep wine-plum upholstered walls (read bright pink-lavender), mahogany wood walls instead of flat plaster, cream tray field, black-gold marble tub deck/floor instead of white-vein black
P5['wego-linsen-746b0ccf04bf']=function(x)
 for _,side in ipairs({'left','right'})do
  local w=wall(x,side,function(w)return type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='tufted' end)
  if w then w.mat={gen={kind='tufted',bg={0.2,0.03,0.1},fg={0.34,0.05,0.18},line={0.1,0.02,0.06}},tile=0.6,rough=0.45} end
 end
 x.wall={gen={kind='wood',c1={0.34,0.11,0.05},c2={0.27,0.08,0.04},rows=3},tile=1.6,rough=0.25}
 if x.ceiling then x.ceiling.field={color={0.86,0.78,0.64},rough=0.8,emit=0.25} end
 if x.bath then
  local bg={gen={kind='marble',base={0.08,0.06,0.05},dark={0.03,0.02,0.02},vein={0.75,0.6,0.35}},tile=1.2,rough=0.12}
  x.bath.surround=bg;x.bath.floor=bg;x.bath.counter=bg
 end
end
-- 405 戀戀瑪姬: dusty-pink satin vertical panels (lavender square grid read like bath tiles), drop the white square grid behind the bed (photo has the same pleat panels there), champagne-rose leather sofas, bright silver-white tray field with mirror medallions round both chandeliers, softer violet accent
P5['wego-linsen-3480fecda6b2']=function(x)
 x.wall={gen={kind='stripes',bg={0.8,0.66,0.72},c2={0.9,0.8,0.82},width=96},tile=2.0,rough=0.35}
 x.extras=drop(x.extras,function(e)return e.type=='padded_wall' and e.side=='rear' end)
 if x.living and x.living.seats then
  for _,s in ipairs(x.living.seats)do if s.kind=='chesterfield' then s.mat={color={0.55,0.42,0.33},rough=0.3,metal=0.2} end end
 end
 if x.ceiling then
  x.ceiling.field={color={0.9,0.87,0.9},rough=0.7,emit=0.35}
  x.ceiling.soffit={color={0.94,0.92,0.94},rough=0.6}
  x.ceiling.ovals={{at={2.3,-0.6},r={0.8,0.8},mat={color={0.85,0.85,0.88},rough=0.1,metal=0.8}},{at={-3.34,3.4},r={0.7,0.7},mat={color={0.85,0.85,0.88},rough=0.1,metal=0.8}}}
 end
 if x.light and x.light.accents then
  for _,a in ipairs(x.light.accents)do a.color={1.0,0.6,0.95};a.lm=600 end
 end
end
-- 406 第五元素: the white rounded portal is a smooth slab frame, not a brick semicircle (voussoirs read as a stack of blocks) -> piers on the old footprint + lintel + corner fillets; white ceiling field with more white cube pendants in the red slots; olive-grey (not teal) stripes; stronger beige check in the bath
P5['wego-linsen-5478372036a4']=function(x)
 x.extras=drop(x.extras,function(e)return e.type=='brick_arch' end)
 local W={color={0.95,0.95,0.94},rough=0.25}
 add(x,{type='box',name='Arch portal pier',at={-6.74,1.4,1.7},size={0.3,0.25,3.4},mat=W,bevel=0.06})
 add(x,{type='box',name='Arch portal pier',at={0.06,1.4,1.7},size={0.3,0.25,3.4},mat=W,bevel=0.06})
 add(x,{type='box',name='Arch portal lintel',at={-3.34,1.4,3.58},size={7.1,0.5,0.44},mat=W,bevel=0.08})
 add(x,{type='box',name='Arch portal fillet',at={-6.37,1.4,3.12},size={0.45,0.25,0.45},mat=W,bevel=0.12})
 add(x,{type='box',name='Arch portal fillet',at={-0.31,1.4,3.12},size={0.45,0.25,0.45},mat=W,bevel=0.12})
 for _,px in ipairs({-4.7,-3.34,-2.0})do
  add(x,{type='box',name='White cube pendant',at={px,2.05,3.35},size={0.16,0.16,0.6},mat={color={1.0,0.98,0.95},emit=3.0}})
  add(x,{type='box',name='White cube pendant',at={px,3.15,3.1},size={0.16,0.16,1.1},mat={color={1.0,0.98,0.95},emit=3.0}})
 end
 x.wall={gen={kind='stripes',bg={0.64,0.64,0.56},c2={0.46,0.47,0.41},width=48},tile=1.0,rough=0.45}
 if x.ceiling then
  x.ceiling.field={color={0.93,0.92,0.9},rough=0.7,emit=0.35}
  x.ceiling.soffit={color={0.95,0.95,0.94},rough=0.5}
 end
 if x.bath then x.bath.wall={gen={kind='check',bg={0.76,0.72,0.6},fg={0.48,0.45,0.37},n=6},tile=1.0,rough=0.3} end
end
-- 407 鉑金屋: smoked black faceted mirror walls (lattice became a lavender-grey quilt) -> dark metal mirror + wide chrome facet seams; cream tray field; black mosaic tub deck instead of white-vein marble
P5['wego-linsen-f056fc3ebee2']=function(x)
 local MIR={color={0.05,0.05,0.06},rough=0.04,metal=1.0}
 local CHROME={color={0.7,0.7,0.75},rough=0.1,metal=1.0}
 local w=wall(x,'left');if w then w.mat=MIR end
 w=wall(x,'right');if w then w.mat=MIR end
 add(x,{type='trellis',side='left',range={-3.0,6.2},z={0.25,3.35},back='none',off=0.04,pitch=1.3,bar=CHROME})
 add(x,{type='trellis',side='right',range={-4.4,1.6},z={0.25,3.35},back='none',off=0.04,pitch=1.3,bar=CHROME})
 if x.ceiling then
  x.ceiling.field={color={0.9,0.88,0.86},rough=0.75,emit=0.3}
  x.ceiling.soffit={color={0.92,0.9,0.88},rough=0.6}
 end
 if x.bath then x.bath.surround={gen={kind='mosaic',colors={{0.06,0.06,0.08},{0.1,0.1,0.12}},tiles=24},tile=1.0,rough=0.15} end
end
-- 408 沉睡森林: dark mossy shag rug (was neon green), warm cream tray field, wenge wood walls, low wide dark-wood headboard band with black drum shades, plain black tub deck
P5['wego-linsen-032c87705ea0']=function(x)
 if x.living and x.living.rug then x.living.rug.mat={gen={kind='plaster',c1={0.12,0.15,0.08},c2={0.07,0.09,0.05}},tile=1.0,rough=1.0} end
 if x.ceiling then
  x.ceiling.field={color={0.88,0.8,0.6},rough=0.8,emit=0.35}
  x.ceiling.soffit={color={0.9,0.85,0.72},rough=0.7}
 end
 x.wall={gen={kind='wood',c1={0.16,0.11,0.08},c2={0.12,0.08,0.06},rows=4},tile=1.6,rough=0.4}
 if x.bed then
  x.bed.headboard={type='panel',mat={color={0.14,0.09,0.06},tex='wood_dark',tile=1.4,rough=0.35},w=4.4,h=1.0}
  x.bed.shade={color={0.18,0.15,0.12},emit=0.8}
 end
 if x.bath then x.bath.surround={color={0.03,0.03,0.035},rough=0.1} end
end
-- 409 祕密花園: mossy (not neon) green shag, cream-white tray field under the green-white cove, warmer beige-gold damask, champagne tufted oval ottoman on the rug (signature piece, at the coffee-table spot)
P5['wego-linsen-d5cd0d1d657b']=function(x)
 if x.living and x.living.rug then x.living.rug.mat={gen={kind='plaster',c1={0.14,0.3,0.1},c2={0.08,0.2,0.06}},tile=1.0,rough=1.0} end
 if x.ceiling then
  x.ceiling.field={color={0.92,0.9,0.84},rough=0.75,emit=0.35}
  x.ceiling.soffit={color={0.92,0.9,0.85},rough=0.6}
 end
 x.wall={gen={kind='damask',bg={0.76,0.66,0.48},fg={0.86,0.8,0.66}},tile=1.2,rough=0.55}
 if x.living and not x.living.table then
  local champ={gen={kind='tufted',bg={0.55,0.45,0.3},fg={0.68,0.57,0.4},line={0.3,0.22,0.12}},tile=0.5,rough=0.4}
  x.living.table={kind='round_drum',at={2.3,-1.0},size={1.2,1.2},mat=champ,base=champ}
 end
end
-- 410 東方之珠: black wallpaper with grey cloud scrolls (fine grey lattice) -> damask; cream-gold tray field; dark slate tub deck/floor instead of white-vein marble; thicker red bamboo
P5['wego-linsen-84caf6ee7228']=function(x)
 x.wall={gen={kind='damask',bg={0.07,0.06,0.06},fg={0.36,0.34,0.31}},tile=1.4,rough=0.6}
 if x.ceiling then
  x.ceiling.field={color={0.88,0.8,0.6},rough=0.8,emit=0.35}
  x.ceiling.soffit={color={0.9,0.84,0.7},rough=0.7}
 end
 if x.bath then
  x.bath.surround={color={0.05,0.05,0.05},rough=0.25}
  x.bath.floor={gen={kind='plaster',c1={0.12,0.12,0.12},c2={0.08,0.08,0.08}},tile=1.0,rough=0.3}
 end
 for i,e in ipairs(x.extras or {})do
  if e.type=='box' and e.name=='Red bamboo' then
   e.size={0.085,0.085,3.8};e.mat={color=(i%2==0) and {0.72,0.05,0.05} or {0.82,0.1,0.07},rough=0.3}
  end
 end
end
-- 411 黑色狂想曲: black glitter square padded panels behind the bed (auto diamonds read light grey), cream tray border round the star vault, plain black tub deck instead of purple-vein marble
P5['wego-linsen-6164fc53475c']=function(x)
 local w=wall(x,'rear');if w then w.flat=true;w.mat={color={0.03,0.03,0.035},rough=0.3} end
 add(x,{type='padded_wall',side='rear',range={-7.0,0.0},z={0.4,3.3},pattern='rect',size=0.6,mats={{color={0.06,0.06,0.07},rough=0.25,metal=0.5},{color={0.08,0.08,0.09},rough=0.3,metal=0.5}}})
 if x.ceiling then x.ceiling.soffit={color={0.88,0.84,0.76},rough=0.6} end
 if x.bath then x.bath.surround={color={0.03,0.03,0.035},rough=0.1} end
end

-- 412 伊莉莎白: wine-red (not bright red) velvet walls/drape, cream tray ceiling with white crown trim, red bedside lamp glow
P5['wego-linsen-c0b570262fc7']=function(x)
 x.wall={gen={kind='stripes',bg={0.32,0.02,0.04},c2={0.22,0.012,0.028},width=30},tile=1.0,rough=0.85}
 for _,e in ipairs(x.extras or {})do if e.type=='drape' then e.mat={color={0.3,0.015,0.035},rough=0.85};e.folds=26 end end
 local w=wall(x,'right',function(w)return w.mat and w.mat.gen and w.mat.gen.kind=='damask' end)
 if w then w.mat={gen={kind='damask',bg={0.3,0.02,0.04},fg={0.5,0.05,0.08}},tile=1.6,rough=0.7} end
 if x.ceiling then
  x.ceiling.field={color={0.95,0.9,0.76},rough=0.8,emit=0.35}
  x.ceiling.soffit={color={0.96,0.93,0.86},rough=0.8}
  x.ceiling.trim={color={0.95,0.92,0.85},rough=0.5}
 end
 if x.bed then x.bed.lamps='drum';x.bed.shade={color={0.9,0.08,0.06},emit=2.0} end
 x.light=x.light or {};x.light.lamp={1.0,0.42,0.28}
end
-- 413 巴洛克: the side walls are big white baroque damask that glows on black (read as small purple dots), pink-white tray field, dark grey bath mosaic
P5['wego-linsen-184b589e8e91']=function(x)
 for _,w in ipairs(x.walls or {})do
  if w.mat and w.mat.gen and w.mat.gen.kind=='damask' then w.mat={gen={kind='damask',bg={0.015,0.01,0.02},fg={0.97,0.92,0.97}},tile=2.8,emit=1.6,rough=0.3} end
 end
 if x.ceiling then x.ceiling.field={color={0.93,0.85,0.93},rough=0.8,emit=0.3};x.ceiling.soffit={color={0.95,0.9,0.95},rough=0.8} end
 if x.bath then x.bath.floor={gen={kind='mosaic',colors={{0.16,0.16,0.18},{0.23,0.23,0.25}},tiles=30,grout={0.1,0.1,0.11}},tile=1.0,rough=0.2} end
end
-- 414 芭比盛宴: black wavy-lacquer frames between the wall mirrors, white headboard with black framed mirror above, cream-pink tray field
P5['wego-linsen-42359812d664']=function(x)
 local lac={color={0.02,0.015,0.02},rough=0.08,metal=0.2}
 -- names contain 'Mirror' so footprints()/furnish ignore them (wall-mounted, 8 cm deep)
 for _,y in ipairs({-3.0,-0.75,1.5,3.75,6.0})do add(x,{type='box',name='Mirror pilaster lacquer',at={-7.33,y,1.8},size={0.08,0.32,2.6},mat=lac,bevel=0.03}) end
 add(x,{type='box',name='Mirror cornice lacquer',at={-7.33,1.5,3.1},size={0.08,9.4,0.18},mat=lac,bevel=0.03})
 for _,y in ipairs({-4.4,-2.4,-0.4,1.6})do add(x,{type='box',name='Mirror pilaster lacquer',at={7.33,y,1.8},size={0.08,0.32,2.6},mat=lac,bevel=0.03}) end
 add(x,{type='box',name='Mirror cornice lacquer',at={7.33,-1.4,3.1},size={0.08,6.2,0.18},mat=lac,bevel=0.03})
 if x.bed and x.bed.headboard then x.bed.headboard.mat={color={0.95,0.93,0.93},rough=0.6};x.bed.headboard.button={color={0.75,0.12,0.38},rough=0.5} end
 add(x,{type='frames',side='rear',n=1,range={-3.84,-2.84},z=2.2,size={0.75,0.95},art={color={0.72,0.72,0.75},rough=0.03,metal=1.0},frame={color={0.02,0.02,0.02},rough=0.2}})
 if x.ceiling then x.ceiling.field={color={0.96,0.88,0.9},rough=0.8,emit=0.3};x.ceiling.soffit={color={0.96,0.92,0.9},rough=0.8} end
end
-- 415 浪漫地中海: bright orange wood-slat ceiling (was near black), warm gold stripe headwall with a gold rod, a full row of gilt paintings
P5['wego-linsen-6e1c37b80fda']=function(x)
 if x.ceiling then
  x.ceiling.field={gen={kind='stripes',bg={0.92,0.6,0.36},c2={0.7,0.4,0.22},width=10},tile=1.0,rough=0.6,emit=0.35}
  x.ceiling.soffit={color={0.96,0.9,0.75},rough=0.8}
 end
 local stripe={gen={kind='stripes',bg={0.95,0.8,0.38},c2={0.8,0.6,0.22},width=24},tile=1.0,rough=0.7}
 for _,w in ipairs(x.walls or {})do if w.mat and w.mat.gen and w.mat.gen.kind=='stripes' then w.mat=stripe end end
 -- rods at 1.86 m (footprints skip boxes whose bottom is above 1.8 m)
 add(x,{type='box',name='Headwall gold rod',at={-3.5,6.47,1.86},size={7.4,0.05,0.05},mat=GOLD})
 add(x,{type='box',name='Headwall gold rod',at={-7.34,1.65,1.86},size={0.05,9.7,0.05},mat=GOLD})
 for _,e in ipairs(x.extras or {})do if e.type=='frames' and e.side=='rear' then e.n=5;e.range={-7.0,0.0};e.size={0.7,0.55};e.z=2.5 end end
end
-- 416 水晶迷情: dark navy button-tufted headwall with small diamonds (was big bright violet blocks), white tray field, deeper blue niche
P5['wego-linsen-8caf5f81400a']=function(x)
 local w=wall(x,'rear',function(w)return w.mat and w.mat.gen and w.mat.gen.kind=='tufted' end)
 if w then w.flat=true;w.mat={gen={kind='tufted',bg={0.03,0.03,0.1},fg={0.05,0.05,0.15},line={0.02,0.02,0.06}},tile=0.5,rough=0.7} end
 add(x,{type='padded_wall',side='rear',range={-4.95,-1.75},z={0.5,3.2},pattern='diamond',size=0.26,mats={{color={0.05,0.05,0.18},rough=0.75},{color={0.04,0.04,0.15},rough=0.75}},button={color={0.82,0.82,0.86},rough=0.2,metal=0.9}})
 if x.ceiling then x.ceiling.field={color={0.93,0.94,0.98},rough=0.8,emit=0.3};x.ceiling.soffit={color={0.95,0.95,0.97},rough=0.8} end
 for _,e in ipairs(x.extras or {})do if e.type=='screen' then e.mat={color={0.12,0.2,1.0},emit=1.6} end end
end
-- 501 夜上海: big red peonies (print was tiny dots), gilt ceiling field (metal read black), bronze ring beside the fan headboard, swagged tie-back drape
P5['wego-linsen-28559135de57']=function(x)
 x.wall={gen={kind='floral',bg={0.35,0.02,0.04},fg={0.85,0.08,0.1},fg2={0.6,0.04,0.06}},tile=3.0,rough=0.7}
 if x.ceiling then
  x.ceiling.field={gen={kind='damask',bg={0.82,0.66,0.3},fg={0.95,0.82,0.45}},tile=1.0,rough=0.45,emit=0.35}
  x.ceiling.soffit={color={0.95,0.9,0.78},rough=0.8}
 end
 for _,e in ipairs(x.extras or {})do
  if e.type=='neon' and e.shape=='circle' then e.at={-2.5,0};e.z=1.9;e.size=1.4;e.color={0.5,0.38,0.16} end
  if e.type=='drape' and e.y and e.y>6 then e.tie=1.25;e.valance=true;e.folds=16;e.mat={color={0.72,0.6,0.38},rough=0.8} end
 end
 if x.bath then x.bath.wall={gen={kind='floral',bg={0.93,0.89,0.8},fg={0.55,0.6,0.75},fg2={0.8,0.6,0.3}},tile=0.6,rough=0.3} end
end
-- 502 天使之約: lit mirror-grid ceiling (pink/violet mullions), soft lilac damask instead of hot-pink floral, gold skirt, gold tufted swing bed
P5['wego-linsen-3edf41ae9233']=function(x)
 x.wall={gen={kind='damask',bg={0.86,0.82,0.85},fg={0.92,0.89,0.91}},tile=1.2,rough=0.7}
 if x.ceiling then x.ceiling.cove={1.0,0.35,0.85} end
 local z=3.8
 for _,gx in ipairs({-5.4,-3.6,-1.8,0.0,1.8,3.6,5.4})do add(x,{type='led_line',a={gx,-4.4,z},b={gx,6.4,z},color={0.8,0.5,1.0},emit=5}) end
 for _,gy in ipairs({-4.4,-2.6,-0.8,1.0,2.8,4.6,6.4})do add(x,{type='led_line',a={-5.4,gy,z},b={5.4,gy,z},color={0.8,0.5,1.0},emit=5}) end
 if x.bed then x.bed.base={color={0.85,0.68,0.35},rough=0.7} end
 for _,e in ipairs(x.extras or {})do if e.type=='swing_bed' then e.mat={color={0.86,0.74,0.45},rough=0.35,metal=0.35} end end
 -- the flat 'Tufted swing bed' slab duplicated the real swing bed in the middle of the living area
 x.extras=drop(x.extras,function(e)return e.type=='box' and e.name=='Tufted swing bed' end)
 if x.light and x.light.accents then for _,a in ipairs(x.light.accents)do a.lm=700 end end
end
-- 503 加州陽光: tan diamond-paper ceiling (read black), large gold-framed cream wall panels (was a 0.33 m grid), gold headboard, prints over the bed
P5['wego-linsen-d44fca1aeab6']=function(x)
 if x.ceiling then
  x.ceiling.field={gen={kind='lattice',bg={0.88,0.74,0.55},fg={0.96,0.86,0.68}},tile=0.6,rough=0.7,emit=0.35}
  x.ceiling.soffit={color={0.97,0.95,0.9},rough=0.8}
 end
 local w=wall(x,'rear',function(w)return w.mat and w.mat.gen and w.mat.gen.kind=='panels' end)
 if w then w.mat={gen={kind='panels',bg={0.92,0.86,0.72},fg={0.72,0.58,0.3},n=2},tile=2.8,rough=0.7} end
 x.wall={gen={kind='stripes',bg={0.92,0.84,0.68},c2={0.88,0.79,0.62},width=24},tile=1.0,rough=0.7}
 if x.bed and x.bed.headboard then x.bed.headboard.mat={color={0.8,0.64,0.36},rough=0.55};x.bed.headboard.button={color={0.6,0.45,0.2},rough=0.4} end
 for _,e in ipairs(x.extras or {})do if e.type=='frames' and e.side=='rear' then e.range={-4.4,-2.3};e.z=2.3;e.size={0.5,0.65} end end
end
-- 504 情定巴里島: warm wood-slat tray ceiling with cove (beams read black), orange burl-wood walls, the three dark-framed prints over the bed
P5['wego-linsen-d9a79d4622a2']=function(x)
 x.ceiling={type='tray',band=1.0,cove={1.0,0.72,0.4},cove_emit=7.0,
  field={gen={kind='wood',c1={0.78,0.48,0.22},c2={0.66,0.38,0.16},rows=12},tile=2.0,rough=0.5,emit=0.3},
  soffit={color={0.35,0.18,0.08},tex='wood_dark',tile=1.0,rough=0.4}}
 x.wall={gen={kind='marble',base={0.88,0.5,0.16},dark={0.62,0.3,0.08},vein={0.98,0.72,0.32},scale=9},tile=1.8,rough=0.4}
 for _,e in ipairs(x.extras or {})do if e.type=='frames' then e.side='rear';e.range={-4.7,-2.0};e.z=2.05;e.size={0.42,0.58};e.art={color={0.9,0.85,0.72},rough=0.6} end end
end

-- 505 凡賽斯: quilted gold diamond headboard panel (photo) instead of bare printed lattice; deep Emperador-brown bath marble (bath read crimson); warm cream ceiling field
P5['wego-linsen-cc741722fce3']=function(x)
 x.walls=drop(x.walls,function(w)return w.side=='rear' and w.mat.gen and w.mat.gen.kind=='lattice' end)
 add(x,{type='panel',side='rear',x0=-5.3,x1=-1.4,z0=0.3,z1=1.65,mat={color={0.14,0.08,0.05},tex='wood_dark',tile=1.0,rough=0.35}})
 add(x,{type='padded_wall',side='rear',range={-5.0,-1.7},z={0.45,1.45},pattern='diamond',size=0.3,
  mats={{color={0.78,0.62,0.32},rough=0.35,metal=0.35},{color={0.68,0.53,0.26},rough=0.35,metal=0.35}},frame='gold'})
 add(x,{type='trellis',side='rear',range={-5.0,-1.7},z={0.4,1.5},back='none',off=0.16,pitch=0.42,bar=GOLD})
 x.ceiling.field={color={0.93,0.88,0.74},rough=0.7}
 x.ceiling.cove={1.0,0.85,0.45}
 x.bath.wall='marble_redbrown'
 x.bath.surround='marble_redbrown'
 x.bath.floor={gen={kind='mosaic',colors={{0.3,0.2,0.14},{0.22,0.15,0.1},{0.4,0.28,0.18}},tiles=12,grout={0.08,0.05,0.04}},tile=1.0,rough=0.15,metal=0.6}
end
-- 506 愛麗斯派對: silver pleated fan headboard rising at the edges (was a round disc); magenta oval recess with copper rim over the bed in a gold-beige ceiling; warm yellow cove instead of pink (walls read pink/olive); brighter cream-gold damask
P5['wego-linsen-81a03257f229']=function(x)
 local SILVER={color={0.82,0.82,0.86},rough=0.22,metal=0.55}
 x.bed.headboard={type='slats',mat=SILVER,w=2.6,h=1.5}
 add(x,{type='box',name='Fan headboard backing',at={-3.34,6.2,1.125},size={2.3,0.1,1.45},mat=SILVER,bevel=0.04})
 for _,st in ipairs({{0.95,2.05},{1.22,2.3},{1.47,2.55}})do
  for _,s in ipairs({-1,1})do
   add(x,{type='box',name='Fan headboard wing',at={-3.34+s*st[1],6.2,(0.4+st[2])/2},size={0.3,0.1,st[2]-0.4},mat=SILVER,bevel=0.05})
  end
 end
 local c=x.ceiling
 c.type='tray';c.domes=arr({});c.dome_field=nil
 c.field={color={0.8,0.68,0.45},rough=0.7}
 c.cove={1.0,0.82,0.45}
 c.ovals={{at={-3.34,3.0},r={2.0,1.3},mat={color={0.95,0.25,0.9},emit=3.0},cove={1.0,0.3,0.95}}}
 x.wall={gen={kind='damask',bg={0.86,0.74,0.52},fg={0.94,0.84,0.62}},tile=0.9,rough=0.6}
 x.light.accents={{at={-3.34,3.0,3.3},color={1.0,0.3,0.9},lm=700,r=500}}
end
-- 507 美國舞孃: room is black with ONE red sequin wall (all walls were red mosaic); dark bead curtain + purple ring canopy over the round stage; black glossy bath mosaic (white grout made it lilac)
P5['wego-linsen-5bd7fd739cb0']=function(x)
 x.wall={gen={kind='stripes',bg={0.05,0.04,0.04},c2={0.09,0.07,0.06},width=24,vertical=true},tile=1.0,rough=0.3}
 x.walls=x.walls or arr({})
 x.walls[#x.walls+1]={side='left',x0=-3.2,x1=6.4,mat={gen={kind='mosaic',colors={{0.42,0.03,0.04},{0.68,0.08,0.07},{0.25,0.02,0.03},{0.9,0.3,0.25}},tiles=96,grout={0.08,0.01,0.01}},tile=1.0,rough=0.15,metal=0.6}}
 for _,e in ipairs(x.extras)do if e.type=='fiber_curtain' then e.color={0.16,0.03,0.24} end end
 x.chandeliers=x.chandeliers or arr({})
 x.chandeliers[#x.chandeliers+1]={kind='ring',at={-5.2,-1.6},glow={0.65,0.2,1.0}}
 x.bath.wall={gen={kind='mosaic',colors={{0.03,0.03,0.035},{0.08,0.08,0.09},{0.3,0.28,0.24}},tiles=24,grout={0.02,0.02,0.02}},tile=1.0,rough=0.12}
 x.bath.surround={gen={kind='mosaic',colors={{0.04,0.04,0.05},{0.14,0.14,0.15},{0.45,0.45,0.47}},tiles=60,grout={0.03,0.03,0.03}},tile=1.0,rough=0.12}
end
-- 508 蝴蝶夫人: purple-brown damask fabric full height behind the bed (white stone band there was wrong); white chiselled stone band + violet LED behind the lounge sofa; brown sofa with peach cushions on a dark-wood platform with blue LED edge
P5['wego-linsen-1bf22b916626']=function(x)
 local w=wall(x,'rear')
 if w then w.mat={gen={kind='damask',bg={0.24,0.15,0.15},fg={0.42,0.28,0.46}},tile=0.9,rough=0.8};w.z0=nil;w.z1=nil end
 add(x,{type='panel',side='left',x0=-3.2,x1=0.2,z0=1.05,z1=1.85,mat={gen={kind='brick',bg={0.8,0.78,0.74},fg={0.93,0.91,0.87}},tile=0.5,rough=0.95}})
 add(x,{type='led_line',a={-7.36,-3.2,1.9},b={-7.36,0.2,1.9},color={0.5,0.35,1.0},emit=8})
 if x.living and x.living.seats and x.living.seats[1] then x.living.seats[1].mat={color={0.36,0.25,0.18},rough=0.8} end
 for _,yy in ipairs({-2.9,-2.1,-1.1,-0.3})do
  add(x,{type='box',name='Sofa cushion',at={-5.95,yy,0.72},size={0.2,0.45,0.42},mat={color={0.88,0.5,0.3},rough=0.85},bevel=0.08})
 end
 for _,e in ipairs(x.extras)do if e.name=='Lounge platform' then e.mat={color={0.32,0.2,0.11},tex='wood_dark',tile=1.0,rough=0.35} end end
 add(x,{type='box',name='Lounge platform blue edge',at={-4.0,-1.6,0.03},size={0.04,4.4,0.04},mat={color={0.3,0.3,1.0},emit=7.0}})
end
-- 509 熱情夏威夷: brick facing + green marble and glowing tropical recess inside the brick arch (arch sat on a plain grey garage wall); warm wood tray field that does not go black, white cove; gold damask curtain on the window wall
P5['wego-linsen-d96d3a37a4a7']=function(x)
 local BRICK={gen={kind='brick',bg={0.3,0.15,0.1},fg={0.55,0.28,0.18}},tile=1.0,rough=0.85}
 add(x,{type='box',name='Arch brick facing lining',at={-3.8,-3.235,1.45},size={6.1,0.03,2.9},mat=BRICK})
 add(x,{type='box',name='Arch recess marble lining',at={-4.0,-3.215,0.775},size={3.2,0.02,1.55},mat={gen={kind='marble',base={0.12,0.25,0.18},dark={0.05,0.12,0.08},vein={0.6,0.75,0.6}},tile=1.2,rough=0.12}})
 local TROP={gen={kind='floral',bg={0.95,0.82,0.3},fg={0.12,0.5,0.2},fg2={0.15,0.35,0.75}},tile=1.0,emit=0.9,rough=0.6}
 for _,b in ipairs({{1.55,2.1,1.5},{2.1,2.5,1.1},{2.5,2.75,0.6}})do
  add(x,{type='box',name='Arch recess tropical lining',at={-4.0,-3.215,(b[1]+b[2])/2},size={2*b[3],0.02,b[2]-b[1]},mat=TROP})
 end
 x.ceiling.field={gen={kind='wood',c1={0.78,0.55,0.3},c2={0.66,0.45,0.24},rows=28},tile=1.6,rough=0.5,emit=0.35}
 x.ceiling.cove={1.0,0.97,0.9};x.ceiling.cove_emit=9.0
 add(x,{type='drape',axis='y',x0=-4.2,x1=1.4,y=7.25,z1=3.5,folds=14,mat={gen={kind='damask',bg={0.42,0.34,0.16},fg={0.7,0.58,0.3}},tile=0.7,rough=0.85}})
end
-- 510 情定巴里島: honey wood-plank tray ceiling with amber cove under a dark wood cornice (beams rendered black); warmer tan woven wallpaper (read olive); honey floor (read grey); dark wood wainscot
P5['wego-linsen-c4c23c00c947']=function(x)
 x.ceiling={type='tray',band=1.2,cove={1.0,0.62,0.25},cove_emit=8.0,
  field={gen={kind='wood',c1={0.72,0.45,0.22},c2={0.6,0.36,0.17},rows=30},tile=1.4,rough=0.45,emit=0.3},
  soffit={color={0.28,0.14,0.06},tex='wood_dark',tile=1.0,rough=0.4},trim={color={0.25,0.12,0.05},rough=0.4}}
 x.wall={gen={kind='lattice',bg={0.84,0.66,0.44},fg={0.74,0.56,0.36}},tile=0.4,rough=0.8}
 x.floor={gen={kind='wood',c1={0.6,0.4,0.22},c2={0.48,0.3,0.16},rows=10},tile=2.0,rough=0.35}
 add(x,{type='wainscot',sides={'left'},h=0.95,mat={color={0.2,0.1,0.05},tex='wood_dark',tile=1.2,rough=0.4},rail={color={0.25,0.13,0.06},rough=0.4}})
end
-- 511 幻鏡撲克: three bulb-framed arch mirrors on the visible left wall (the auto one landed in the garage); solid-looking red hearts (concentric neon fill, were thin pink outlines); dark emerald vertical glazed bath tiles (stripes were neon green)
P5['wego-linsen-13139aa6a1d8']=function(x)
 for _,e in ipairs(x.extras)do if e.type=='arch_mirror' and not e.at then e.at={-7.0,-0.75} end end
 add(x,{type='arch_mirror',bulbs=true,at={-7.0,-2.4}})
 add(x,{type='arch_mirror',bulbs=true,at={-7.0,2.6}})
 local hearts={}
 for _,e in ipairs(x.extras)do if e.type=='neon' and (e.shape==nil or e.shape=='heart') then hearts[#hearts+1]=e end end
 for _,e in ipairs(hearts)do
  e.color={1.0,0.04,0.06}
  local s=(e.size or 0.6)-0.05
  while s>0.08 do add(x,{type='neon',side=e.side,at=e.at,z=e.z,size=s,color={1.0,0.04,0.06}});s=s-0.05 end
 end
 x.bath.wall={gen={kind='stripes',bg={0.03,0.15,0.09},c2={0.05,0.21,0.13},width=18,vertical=true},tile=1.0,rough=0.08,metal=0.2}
end
-- 513 月球漫步: vertical blue light streaks in the bubble panel (galaxy print tiled into squares); black glitter floor and navy ceiling (read grey/lilac); dark grout on all navy sequin mosaics (light grout made them lilac); thicker gold rings
P5['wego-linsen-01b7b50e547d']=function(x)
 for _,e in ipairs(x.extras)do if e.name=='Bubble light panel' then e.mat={gen={kind='stripes',bg={0.04,0.18,0.5},c2={0.55,0.88,1.0},width=10,vertical=true},tile=1.0,emit=2.5,rough=0.05} end end
 x.floor={gen={kind='mosaic',colors={{0.03,0.03,0.05},{0.06,0.06,0.09},{0.35,0.32,0.28}},tiles=120,grout={0.02,0.02,0.03}},tile=1.0,rough=0.15,metal=0.3}
 x.ceiling.field={color={0.03,0.03,0.09},rough=0.35,metal=0.2}
 for _,w in ipairs(x.walls or {})do if type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='mosaic' then w.mat.gen.grout={0.02,0.02,0.05} end end
 if type(x.bath.wall)=='table' and x.bath.wall.gen and x.bath.wall.gen.kind=='mosaic' then x.bath.wall.gen.grout={0.02,0.02,0.05} end
 local rings={}
 for _,e in ipairs(x.extras)do if e.type=='neon' and e.shape=='circle' then rings[#rings+1]=e end end
 for _,e in ipairs(rings)do
  for _,d in ipairs({0.025,0.05})do add(x,{type='neon',side=e.side,at=e.at,z=e.z,size=e.size-d,shape='circle',color=e.color}) end
 end
end
-- 514 土耳其奇浴: candle niches belong in the gold-mosaic bath (they read as stray white bars on the bedroom wall); brown curtain behind the black headboard (was a flat brown board); gold-mosaic oval recess with yellow cove over the bed; warm bath light with purple tub glow; black fur cushions; finer glitter wall
P5['wego-linsen-6f82ad3f8044']=function(x)
 x.extras=drop(x.extras,function(e)return e.name=='Candle niche' end)
 local BRONZE={color={0.15,0.1,0.05},rough=0.15,metal=0.8};local FLAME={color={1.0,0.8,0.3},emit=4.0}
 for _,n in ipairs({{3.3,1.25,0.7},{3.9,2.05,0.5},{5.9,1.35,0.8},{6.6,2.2,0.6},{6.0,1.85,0.35}})do
  add(x,{type='box',name='Bath candle niche',at={n[1],10.145,n[2]},size={n[3]+0.1,0.03,0.3},mat=BRONZE})
  add(x,{type='box',name='Bath candle niche glow',at={n[1],10.125,n[2]-0.04},size={n[3],0.02,0.12},mat=FLAME})
 end
 for _,n in ipairs({{7.6,1.4,0.8},{8.6,2.1,0.6},{9.4,1.2,0.5}})do
  add(x,{type='box',name='Bath candle niche',at={7.345,n[1],n[2]},size={0.03,n[3]+0.1,0.3},mat=BRONZE})
  add(x,{type='box',name='Bath candle niche glow',at={7.325,n[1],n[2]-0.04},size={0.02,n[3],0.12},mat=FLAME})
 end
 x.walls=drop(x.walls,function(w)return w.side=='rear' and w.z0==1.4 end)
 add(x,{type='drape',x0=-4.3,x1=-2.4,y=6.36,z1=3.4,folds=12,mat={color={0.2,0.11,0.06},rough=0.85}})
 x.ceiling.ovals={{at={-3.34,4.2},r={1.8,1.3},mat='mosaic_gold',cove={1.0,0.82,0.3}}}
 x.light.bath_color={1.0,0.88,0.6}
 x.bath.glow={0.7,0.4,1.0}
 for _,p in ipairs({{1.6,0.75,0.75,0.45,0.18},{3.0,0.75,0.75,0.45,0.18},{0.32,-0.8,0.75,0.18,0.45}})do
  add(x,{type='box',name='Fur cushion',at={p[1],p[2],p[3]},size={p[4],p[5],0.42},mat={color={0.03,0.03,0.03},rough=0.95},bevel=0.08})
 end
 if type(x.wall)=='table' and x.wall.gen then x.wall.gen.tiles=120;x.wall.metal=0.6 end
end
-- 311 溫馨雅閣: red lacquered vine arcade over the entry passage (photo 2): 6 arches on the door axis x=4.41, y -9.7..-6.7,
-- 1.5 m clear (door 1.4), springing at 2.35 m, crown 3.05 m under the 3.55 m soffit; replaces the three brick arches
P5['imore-4994f3264339']=function(x)
 x.extras=drop(x.extras,function(e)return e.type=='brick_arch' end)
 add(x,{type='vine_arcade',at={4.41,-9.7},n=6,pitch=0.6,clear_w=1.5,spring=2.35,rise=0.7,mat={color={0.5,0.05,0.04},rough=0.28,metal=0.05}})
 -- round 7 had no camera on the arcade: look back down it toward the entry like photo 2
 x.views=x.views or {};x.views[#x.views+1]={id='v-entry-arcade',eye={4.41,-4.6,1.65},target={4.41,-10.3,1.95},fov=72}
end
local P6={}
-- ===== pass 6 (2026-10-28): second official-photo review of 401-416, 501-514 (samples 203/209/303/512 untouched); applied after pass 5
-- deep copy into plain tables (json objects keep their key order in a side table, so a copy must not reuse that metatable); arrays stay arrays
local function copy(t)
 if type(t)~='table' then return t end
 local o={};for k,v in pairs(t)do o[k]=copy(v)end
 local mt=getmetatable(t);if mt and mt.__name=='json.array' then o=arr(o) end
 return o
end
-- centre n whole panels of size s inside [a0,a1] (padded_wall fills from u0 and leaves the remainder at the far end)
local function fit(a0,a1,s)local n=math.floor((a1-a0)/s+1e-6);local pad=((a1-a0)-n*s)/2;return {a0+pad-0.001,a1-pad+0.001}end
-- 401 伊莉莎白: cream-white tray field (was red-ground panels), large dark-gold damask scrolls (fine print read as dots), plain black granite tub deck
P6['wego-linsen-5a3ae1f0d9fb']=function(x)
 if x.ceiling then
  x.ceiling.field={color={0.93,0.89,0.8},rough=0.8,emit=0.3}
  x.ceiling.soffit={color={0.96,0.94,0.9},rough=0.8}
 end
 if type(x.wall)=='table' and x.wall.gen and x.wall.gen.kind=='damask' then x.wall.tile=2.4;x.wall.gen.fg={0.6,0.45,0.2} end
 if x.bath then x.bath.surround={color={0.05,0.05,0.05},rough=0.15} end
end
-- 402 第五大道: black and silver wall stripes (were brown-gold)
P6['wego-linsen-97abd5a058ae']=function(x)
 if type(x.wall)=='table' and x.wall.gen and x.wall.gen.kind=='stripes' then x.wall.gen.c2={0.7,0.7,0.72} end
end
-- 403 66號公路: caramel chesterfield copied onto the auto-added sofa/tub chairs (read pale yellow), strong amber cove
P6['wego-linsen-6b8004633136']=function(x)
 if x.living and x.living.seats and x.living.seats[1] then x.living.seats[1].mat={color={0.36,0.18,0.07},rough=0.35} end
 if x.ceiling then x.ceiling.cove={1.0,0.7,0.25};x.ceiling.cove_emit=10.0 end
end
-- 404 威尼斯音樂盒: separate dark-wine square upholstery panels on the side walls (auto diamonds became one bright magenta block with a ragged hem), finer duller gold veins in the black bath marble
P6['wego-linsen-746b0ccf04bf']=function(x)
 for _,side in ipairs({'left','right'})do
  local w=wall(x,side,function(w)return type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='tufted' end)
  if w then
   local d0,d1=side=='left' and -3.2 or -4.6,6.5
   local a0,a1=w.x0 or d0,w.x1 or d1
   w.flat=true;w.mat={color={0.12,0.02,0.07},rough=0.5}
   add(x,{type='padded_wall',side=side,range=fit(a0,a1,0.9),z={w.z0 or 0.9,w.z1 or 3.2},pattern='rect',size=0.9,mats={{color={0.18,0.03,0.1},rough=0.5},{color={0.24,0.04,0.14},rough=0.5}}})
  end
 end
 if x.bath then
  for _,k in ipairs({'wall','floor','counter','surround'})do
   local m=x.bath[k]
   if type(m)=='table' and m.gen and m.gen.kind=='marble' then m.gen.vein={0.45,0.38,0.25};m.tile=0.6 end
  end
 end
end
-- 405 戀戀瑪姬: dark rug lattice at a larger pitch (read solid yellow), champagne-rose (non-metal) chesterfields (read white), purple crystal glow on the arm chandeliers
P6['wego-linsen-3480fecda6b2']=function(x)
 if x.living and x.living.rug and type(x.living.rug.mat)=='table' and x.living.rug.mat.gen and x.living.rug.mat.gen.kind=='lattice' then
  x.living.rug.mat.gen.fg={0.12,0.06,0.03};x.living.rug.mat.tile=1.4
 end
 if x.living and x.living.seats then
  for _,s in ipairs(x.living.seats)do if s.kind=='chesterfield' then s.mat={color={0.48,0.36,0.3},rough=0.3,metal=0.0} end end
 end
 for _,c in ipairs(x.chandeliers or {})do if c.kind=='arms' then c.glow={0.7,0.4,0.9} end end
end
-- 406 第五元素: chunky portal (0.3 m piers read as poles) -> 0.7 x 0.9 m piers widened outward (inner edges keep the route clearance), 0.9 m deep lintel, 0.7 m corner fillets; stepped platform tub on a champagne-gold deck
P6['wego-linsen-5478372036a4']=function(x)
 for _,e in ipairs(x.extras or {})do
  if e.type=='box' and e.name=='Arch portal pier' and e.at then
   if e.at[1]<-3.34 then e.at={-6.9,1.25,1.7} else e.at={0.23,1.25,1.7} end
   e.size={0.7,0.9,3.4};e.bevel=0.08
  elseif e.type=='box' and e.name=='Arch portal lintel' then
   e.at={-3.335,1.25,3.58};e.size={7.83,0.9,0.44}
  elseif e.type=='box' and e.name=='Arch portal fillet' and e.at then
   if e.at[1]<-3.34 then e.at={-6.2,1.25,3.01} else e.at={-0.47,1.25,3.01} end
   e.size={0.7,0.9,0.7};e.bevel=0.3
  end
 end
 if x.bath then x.bath.tub='platform';x.bath.surround={color={0.7,0.6,0.4},rough=0.3,metal=0.5} end
end
-- 407 鉑金屋: small white / pale lilac bath mosaic (the bright 0.55 tile sparkled pink-purple under the pink light)
P6['wego-linsen-f056fc3ebee2']=function(x)
 if x.bath then x.bath.wall={gen={kind='mosaic',colors={{0.86,0.85,0.9},{0.8,0.79,0.86}},tiles=40},tile=1.0,rough=0.15} end
end
-- 408 沉睡森林: ice-blue backlit branch walls (read pure white), khaki auto-added sofa (read mustard), pale purple bath light
P6['wego-linsen-032c87705ea0']=function(x)
 for _,w in ipairs(x.walls or {})do if type(w.mat)=='table' and w.mat.tex=='grok_branch_lightwall' then w.mat.color={0.82,0.9,1.0} end end
 if x.living and x.living.seats and x.living.seats[1] then x.living.seats[1].mat={color={0.5,0.45,0.35},rough=0.85} end
 x.light=x.light or {};x.light.bath_color={0.75,0.7,1.0}
end
-- 409 祕密花園: duller moss rug, smaller darker brown bath brick under amber light, grey-beige damask (read olive)
P6['wego-linsen-d5cd0d1d657b']=function(x)
 if x.living and x.living.rug and type(x.living.rug.mat)=='table' and x.living.rug.mat.gen and x.living.rug.mat.gen.kind=='plaster' then
  x.living.rug.mat.gen.c1={0.09,0.17,0.06};x.living.rug.mat.gen.c2={0.05,0.11,0.04}
 end
 if x.bath and type(x.bath.wall)=='table' and x.bath.wall.gen and x.bath.wall.gen.kind=='brick' then
  x.bath.wall.gen.bg={0.33,0.19,0.14};x.bath.wall.gen.fg={0.48,0.3,0.22};x.bath.wall.tile=0.6
 end
 x.light=x.light or {};x.light.bath_color={1.0,0.7,0.3}
 if type(x.wall)=='table' and x.wall.gen and x.wall.gen.kind=='damask' then x.wall.gen.bg={0.6,0.56,0.48};x.wall.gen.fg={0.7,0.66,0.58} end
end
-- 410 東方之珠: large readable grey cloud scrolls on black, dark stone bath with a black/gold key-pattern band, black lacquer sofa where the auto set put a pale one
P6['wego-linsen-84caf6ee7228']=function(x)
 if type(x.wall)=='table' and x.wall.gen and x.wall.gen.kind=='damask' then x.wall.tile=3.0;x.wall.gen.fg={0.42,0.4,0.36} end
 if x.bath then
  x.bath.wall={color={0.1,0.09,0.08},rough=0.35}
  if x.bath.band then x.bath.band={gen={kind='geo',bg={0.03,0.03,0.03},fg={0.55,0.5,0.4}},tile=1.0,rough=0.3} end
 end
 if x.living then
  x.living.seats=x.living.seats or arr({})
  if #x.living.seats==0 then
   -- where furnish() puts its sofa (default living centre 2.4,-0.5 + 1.45 m); its tub chairs copy this mat
   x.living.seats[1]={kind='modern',at={2.4,0.95},rot=0,len=2.4,mat={color={0.06,0.04,0.04},rough=0.15},legs={color={0.04,0.03,0.03},rough=0.3}}
  else x.living.seats[1].mat={color={0.06,0.04,0.04},rough=0.15} end
 end
end
-- 411 黑色狂想曲: magenta tub glow, deeper grey-black bath walls and floor
P6['wego-linsen-6164fc53475c']=function(x)
 if x.bath then
  x.bath.glow={1.0,0.3,0.9}
  x.bath.wall={color={0.12,0.12,0.13},rough=0.35}
  local f=x.bath.floor
  if type(f)=='table' and f.gen and f.gen.kind=='mosaic' then f.gen.colors={{0.12,0.12,0.13},{0.1,0.1,0.11}};f.gen.grout={0.05,0.05,0.05} else x.bath.floor={color={0.12,0.12,0.13},rough=0.3} end
 end
end
-- 412 伊莉莎白: plain black tub deck (veined marble_black), amber cove
P6['wego-linsen-c0b570262fc7']=function(x)
 if x.bath then x.bath.surround={color={0.03,0.03,0.03},rough=0.1} end
 if x.ceiling then x.ceiling.cove={1.0,0.75,0.3};x.ceiling.cove_emit=10.0 end
end
-- 413 巴洛克: small dark grey bath tiles (read as a pale lilac field), larger brighter glowing damask
P6['wego-linsen-184b589e8e91']=function(x)
 if x.bath then x.bath.wall={gen={kind='mosaic',colors={{0.18,0.18,0.2},{0.26,0.26,0.28}},tiles=40,grout={0.1,0.1,0.11}},tile=1.0,rough=0.2} end
 for _,w in ipairs(x.walls or {})do
  if type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='damask' and w.mat.emit then w.mat.tile=(w.mat.tile or 1.2)*1.5;w.mat.emit=2.2 end
 end
end
-- 414 芭比盛宴: gold fibre curtain (was white)
P6['wego-linsen-42359812d664']=function(x)
 for _,e in ipairs(x.extras or {})do if e.type=='fiber_curtain' then e.color={0.85,0.65,0.3} end end
end
-- 415 浪漫地中海: orange marble bath wall (was a full mural), brighter glowing orange slat ceiling, large terracotta bath floor tiles
P6['wego-linsen-6e1c37b80fda']=function(x)
 if x.bath then
  x.bath.wall={gen={kind='marble',base={0.85,0.55,0.25},dark={0.7,0.4,0.15},vein={0.95,0.8,0.5}},tile=1.2,rough=0.15}
  local f=x.bath.floor
  if type(f)=='table' and f.gen and f.gen.kind=='mosaic' then f.gen.colors={{0.75,0.4,0.2},{0.68,0.35,0.17}};f.gen.tiles=4 end
 end
 local c=x.ceiling
 if c and type(c.field)=='table' and c.field.gen and c.field.gen.kind=='stripes' then c.field.emit=0.8;c.field.gen.bg={0.98,0.72,0.45} end
end
-- 416 水晶迷情: fine dark-navy button tufting (big bright violet blocks), bronze-taupe deep-fold drapes (read white-grey slabs), platform tub
P6['wego-linsen-8caf5f81400a']=function(x)
 for _,e in ipairs(x.extras or {})do
  if e.type=='padded_wall' and e.side=='rear' then e.size=0.18;e.mats={{color={0.03,0.03,0.09},rough=0.75},{color={0.025,0.025,0.08},rough=0.75}} end
  if e.type=='drape' then e.mat={color={0.45,0.4,0.35},rough=0.7,metal=0.0};e.folds=24 end
 end
 if x.bath then x.bath.tub='platform' end
end
-- 501 夜上海: gold pleated fan headboard (read cream), beige tiled bath wall instead of blue-flower paper, peony print with a deeper red ground
P6['wego-linsen-28559135de57']=function(x)
 if x.bed and x.bed.headboard and type(x.bed.headboard.mat)=='table' then x.bed.headboard.mat.color={0.72,0.58,0.3};x.bed.headboard.mat.metal=0.4;x.bed.headboard.mat.rough=0.4 end
 if x.bath then x.bath.wall={gen={kind='mosaic',colors={{0.9,0.84,0.7},{0.86,0.8,0.66}},tiles=12,grout={0.75,0.7,0.6}},tile=1.0,rough=0.2} end
 if type(x.wall)=='table' and x.wall.gen and x.wall.gen.kind=='floral' then x.wall.gen.bg={0.45,0.03,0.05};x.wall.tile=2.0 end
end
-- 502 天使之約: vine-wrapped swing bed, violet LED grid kept inside the tray (x +-4, y -2.5..5), platform tub on a beige mosaic deck
P6['wego-linsen-3edf41ae9233']=function(x)
 for _,e in ipairs(x.extras or {})do if e.type=='swing_bed' then e.vines=true end end
 local had=false
 x.extras=drop(x.extras,function(e)local g=e.type=='led_line' and e.a and e.a[3]==3.8;had=had or g;return g end)
 if had then
  local C={0.85,0.4,1.0}
  for _,gx in ipairs({-4.0,-2.0,0.0,2.0,4.0})do add(x,{type='led_line',a={gx,-2.5,3.8},b={gx,5.0,3.8},color=C,emit=5}) end
  for _,gy in ipairs({-2.5,-0.625,1.25,3.125,5.0})do add(x,{type='led_line',a={-4.0,gy,3.8},b={4.0,gy,3.8},color=C,emit=5}) end
 end
 if x.bath then x.bath.tub='platform';x.bath.surround={gen={kind='mosaic',colors={{0.85,0.75,0.6},{0.8,0.7,0.55}},tiles=60},tile=1.0,rough=0.2} end
end
-- 503 加州陽光: light glowing tan ceiling field (still read dark brown), brighter cove, beige living set (auto sofa read grey), gold-tan headboard (read white)
P6['wego-linsen-d44fca1aeab6']=function(x)
 local c=x.ceiling
 if c then
  if type(c.field)=='table' and c.field.gen and c.field.gen.kind=='lattice' then c.field.gen.bg={0.95,0.85,0.68};c.field.gen.fg={0.99,0.93,0.8};c.field.emit=0.8
  else c.field={color={0.95,0.85,0.68},rough=0.7,emit=0.8} end
  c.cove_emit=9.0
 end
 if x.living and x.living.seats and x.living.seats[1] then x.living.seats[1].mat={color={0.85,0.78,0.62},rough=0.7} end
 if x.bed and x.bed.headboard then x.bed.headboard.mat={color={0.62,0.46,0.22},rough=0.55} end
end
-- 504 情定巴里島: warm amber bath light, dark paintings in black frames over the bed (art read blank)
P6['wego-linsen-d9a79d4622a2']=function(x)
 x.light=x.light or {};x.light.bath_color={1.0,0.8,0.5}
 for _,e in ipairs(x.extras or {})do
  if e.type=='frames' then
   e.art={gen={kind='mural',top={0.25,0.18,0.12},bottom={0.45,0.3,0.18},ground={0.1,0.07,0.05}},fit=true,rough=0.6}
   e.frame={color={0.03,0.03,0.03},rough=0.3}
  end
 end
end
-- 505 凡賽斯: warm (not pink) bedside lamp light, deep brown bath marble with pale veins (redbrown preset read purple-red), brighter cove
P6['wego-linsen-cc741722fce3']=function(x)
 x.light=x.light or {};x.light.lamp={1.0,0.8,0.5}
 if x.bath then
  local m={gen={kind='marble',base={0.3,0.12,0.08},dark={0.15,0.05,0.03},vein={0.9,0.85,0.8}},tile=1.2,rough=0.12}
  x.bath.wall=m;x.bath.surround=copy(m)
 end
 if x.ceiling then x.ceiling.cove_emit=9.0 end
end
-- 506 愛麗斯派對: silver satin wing headboard instead of the seven 'organ pipe' fan boxes, platform tub on a black granite deck
P6['wego-linsen-81a03257f229']=function(x)
 x.extras=drop(x.extras,function(e)return e.type=='box' and (e.name=='Fan headboard wing' or e.name=='Fan headboard backing') end)
 if x.bed then x.bed.headboard={type='wing',mat={color={0.82,0.82,0.86},rough=0.35,metal=0.45},w=2.6,h=1.4} end
 if x.bath then x.bath.tub='platform';x.bath.surround={color={0.05,0.05,0.05},rough=0.15} end
end
-- 507 美國舞孃: a full ring of deep purple bead curtains round the stage (8 x-aligned rows on a 1.8 m circle; widths follow the ring's x extent), glossy black stone bath walls
P6['wego-linsen-5bd7fd739cb0']=function(x)
 local cx,cy,R=-5.2,-1.6,1.8
 for _,e in ipairs(x.extras or {})do if e.type=='platform' and e.at then cx,cy=e.at[1],e.at[2];R=(e.r or 1.7)+0.1 end end
 x.extras=drop(x.extras,function(e)return e.type=='fiber_curtain' end)
 local arc=2*math.pi*R/8
 for k=0,7 do
  local a=math.rad(22.5+45*k)
  add(x,{type='fiber_curtain',at={cx+R*math.cos(a),cy+R*math.sin(a)},w=math.max(0.3,arc*math.abs(math.sin(a))),color={0.16,0.03,0.24}})
 end
 if x.bath then x.bath.wall={color={0.04,0.04,0.045},rough=0.1} end
end
-- 508 蝴蝶夫人: the 'Cherry blossom' box hung at 2.6 m read as a white ball in mid-air -> potted plant on the floor; darker brown-plum damask (read bright purple)
P6['wego-linsen-1bf22b916626']=function(x)
 for _,e in ipairs(x.extras or {})do
  if e.type=='box' and e.name=='Cherry blossom' and e.at then
   local px,py=e.at[1],e.at[2]
   for k in pairs(e)do e[k]=nil end
   e.type='plant';e.at={px,py};e.pot={color={0.15,0.1,0.08},rough=0.5}
  end
 end
 for _,w in ipairs(x.walls or {})do
  if type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='damask' then w.mat.gen.bg={0.14,0.09,0.09};w.mat.gen.fg={0.25,0.17,0.26} end
 end
end
-- 509 熱情夏威夷: darker brick faces on the brick walls and arch facing, deep green tub-deck marble with muted veins (too bright)
P6['wego-linsen-d96d3a37a4a7']=function(x)
 for _,w in ipairs(x.walls or {})do if type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='brick' then w.mat.gen.fg={0.4,0.2,0.13} end end
 for _,e in ipairs(x.extras or {})do
  if e.type=='box' and e.name=='Arch brick facing lining' and type(e.mat)=='table' and e.mat.gen then e.mat.gen.fg={0.4,0.2,0.13} end
 end
 local s=x.bath and x.bath.surround
 if type(s)=='table' and s.gen and s.gen.kind=='marble' then s.gen.base={0.05,0.12,0.08};s.gen.dark={0.02,0.06,0.04};s.gen.vein={0.35,0.5,0.4} end
end
-- 510 情定巴里島: brighter honey slats in the tray field, plain dark tub deck instead of veined marble_black
P6['wego-linsen-c4c23c00c947']=function(x)
 local c=x.ceiling
 if c and type(c.field)=='table' and c.field.gen and c.field.gen.kind=='wood' then c.field.gen.c1={0.85,0.55,0.28};c.field.emit=0.6 end
 if x.bath then x.bath.surround={color={0.08,0.07,0.06},rough=0.2} end
end
-- 511 幻鏡撲克: electric-blue ceiling LED lines (pale blue ones; the orange line stays), brighter; glossy black ceiling instead of the light mirror panel
P6['wego-linsen-13139aa6a1d8']=function(x)
 for _,e in ipairs(x.extras or {})do
  if e.type=='led_line' and e.color and e.color[3]>=0.9 and e.color[1]<0.9 then e.color={0.3,0.55,1.0};e.emit=12 end
 end
 if x.ceiling then
  local G={color={0.02,0.02,0.03},metal=0.6,rough=0.05}
  x.ceiling.type='tray';x.ceiling.field=G;x.ceiling.soffit=copy(G)
 end
end
-- 513 月球漫步: gold (not white) circle neons, tub deck in the same black glitter mosaic as the floor
P6['wego-linsen-01b7b50e547d']=function(x)
 for _,e in ipairs(x.extras or {})do if e.type=='neon' and e.shape=='circle' then e.color={0.95,0.7,0.3} end end
 if x.bath and type(x.floor)=='table' and x.floor.gen and x.floor.gen.kind=='mosaic' then x.bath.surround=copy(x.floor) end
end
-- 514 土耳其奇浴: real gold bath mosaic with dark grout (read pinkish beige), bronze bedroom mosaic (read flat brown), camera on the candle-niche back wall of the bath
P6['wego-linsen-6f82ad3f8044']=function(x)
 local bw=x.bath and x.bath.wall
 if type(bw)=='table' and bw.gen and bw.gen.kind=='mosaic' then
  bw.gen.colors={{0.75,0.58,0.25},{0.7,0.53,0.22},{0.8,0.63,0.3}};bw.gen.grout={0.4,0.3,0.12};bw.metal=0.6
 end
 if type(x.wall)=='table' and x.wall.gen and x.wall.gen.kind=='mosaic' then x.wall.gen.colors={{0.6,0.47,0.25},{0.55,0.42,0.22},{0.66,0.52,0.3}} end
 -- from inside the bath door (left of the tub deck) toward the back-wall and right-wall candle niches
 x.views=x.views or {};x.views[#x.views+1]={id='v-bath-niches',eye={2.9,7.2,1.6},target={5.6,10.1,1.6},fov=80}
end
-- ===== pass 7 (2026-10-29): round-9 packaged-game review (SPEC 12.3); applied after pass 6. A view with a default id replaces that view.
local P7={}
local function view(x,v)x.views=x.views or {};for i=#x.views,1,-1 do if x.views[i].id==v.id then table.remove(x.views,i)end end;x.views[#x.views+1]=v end
-- 404 威尼斯音樂盒: the lavender LED strips showed as white bars under the panels and lit them violet; deeper plum panels, warm bath light
P7['wego-linsen-746b0ccf04bf']=function(x)
 local keep=arr({})
 for _,e in ipairs(x.extras or {})do
  if e.type=='padded_wall' then e.mats={{color={0.15,0.025,0.07},rough=0.6},{color={0.19,0.035,0.09},rough=0.6}} end
  if e.type~='led_strips' then keep[#keep+1]=e end
 end
 x.extras=keep;x.light=x.light or {};x.light.bath_color={1.0,0.85,0.7}
 if x.ceiling then x.ceiling.cove_emit=4.0 end -- round 10: the violet cove still lit the plum panels bright purple
end
-- 405 戀戀瑪姬: dark brown rug ground with gold lattice (only the lines were darkened in pass 6), deeper rose chesterfields (champagne read white under the pink light)
P7['wego-linsen-3480fecda6b2']=function(x)
 local r=x.living and x.living.rug
 if r and type(r.mat)=='table' and r.mat.gen then r.mat.gen.bg={0.2,0.1,0.05};r.mat.gen.fg={0.85,0.65,0.25} end
 for _,s in ipairs(x.living and x.living.seats or {})do if s.kind=='chesterfield' then s.mat={color={0.55,0.42,0.26},rough=0.35,metal=0.3} end end
end
-- 406 第五元素: silver portal (the fillets read as floating capsules), cameras off the right pier: lounge from the TV side, bed head-on through the arch
P7['wego-linsen-5478372036a4']=function(x)
 local keep=arr({})
 for _,e in ipairs(x.extras or {})do
  if e.type=='box' and e.name and e.name:find('^Arch portal') then e.mat={color={0.8,0.8,0.82},rough=0.2,metal=0.6} end
  -- round 11: piers + lintel still read as a square door frame -> one rounded slab portal on the same footprint
  if not (e.type=='box' and e.name and e.name:find('^Arch portal')) then keep[#keep+1]=e end
 end
 keep[#keep+1]={type='portal',x={-7.25,0.58},opening={-6.55,-0.12},y=1.25,depth=0.9,h=3.8,opening_h=3.36,r=1.0,mat={color={0.8,0.8,0.82},rough=0.2,metal=0.6}}
 x.extras=keep
 view(x,{id='v-left-lounge',eye={2.6,-0.9,1.6},target={-6.0,-2.6,0.8},fov=84})
 view(x,{id='v-living-to-bed',eye={-3.34,-3.6,1.7},target={-3.34,4.7,1.0},fov=80})
end
-- 408 沉睡森林: the khaki sofa was a Tripo model with its own mustard texture; build the procedural sofa so the khaki colour applies
P7['wego-linsen-032c87705ea0']=function(x)
 for _,s in ipairs(x.living and x.living.seats or {})do if s.v2=='khaki_long_sofa' then s.v2=nil;s.key=nil;s.mat={color={0.36,0.31,0.22},rough=0.85} end end
end
-- 416 水晶迷情: sheer champagne bead curtains (solid grey drapes read as pillars and blocked v-left-lounge), white-silver bath light
P7['wego-linsen-8caf5f81400a']=function(x)
 -- round 10: the alpha drape still rendered as a solid pillar, so the two drapes become dim bead-strand curtains on the same lines
 local keep=arr({})
 for _,e in ipairs(x.extras or {})do if e.type=='drape' then keep[#keep+1]={type='fiber_curtain',at={(e.x0+e.x1)/2,e.y},w=e.x1-e.x0,color={0.85,0.78,0.6},emit=0.5,r=0.007,pitch=0.035} else keep[#keep+1]=e end end
 x.extras=keep
 x.light=x.light or {};x.light.bath_color={0.92,0.95,1.0}
 view(x,{id='v-left-lounge',eye={2.2,-0.5,1.6},target={-6.0,-2.2,0.8},fov=84})
end
-- 510 情定巴里島: the deck reads as a raised box; dark teak surround and two big potted palms at the back corners (photo: sunk tub among planters)
P7['wego-linsen-c4c23c00c947']=function(x)
 if x.bath then x.bath.surround={color={0.2,0.12,0.06},tex='wood_dark',tile=1.0,rough=0.4};x.bath.ledge_trim={color={0.12,0.07,0.03},rough=0.4} end
 -- round 11: still a raised box -> the low 'sunken' deck on a dark stone floor frame
 if x.bath then x.bath.tub='sunken';x.bath.frame={color={0.08,0.06,0.05},rough=0.2} end
 add(x,{type='plant',at={3.1,9.5},scale=1.8,pot={color={0.35,0.22,0.12},rough=0.7}})
 add(x,{type='plant',at={6.6,9.5},scale=1.8,pot={color={0.35,0.22,0.12},rough=0.7}})
end
-- 513 月球漫步: the whole room in the dark sequin mosaic (photo), gold neon rings (read white)
P7['wego-linsen-01b7b50e547d']=function(x)
 -- round 10: copying the mosaic onto the whole room also blackened the white bed wall; the mosaic stays on the lounge / front walls
 -- round 11: emit 4 still tone-mapped the rings to white; a saturated amber at 1.5 keeps the gold hue
 for _,e in ipairs(x.extras or {})do if e.type=='neon' then e.color={1.0,0.55,0.12};e.emit=1.5 end end
 -- round 11: the hanging white double hoop -> a flush blue ceiling halo (photo 3)
 for _,c in ipairs(x.chandeliers or {})do if c.kind=='ring' then c.kind='halo';c.r=1.4;c.glow={0.12,0.25,1.0};c.emit=2.5 end end
end
-- 312 Candy House: charcoal walls under the white drip frieze, brighter double ceiling neon, two green swirl lollipops beside the round bed
P7['wego-linsen-c3b9042e0d82']=function(x)
 x.wall={color={0.07,0.07,0.09},rough=0.25}
 -- round 11: emit 8 read white-cyan; deep blue at 3
 for _,e in ipairs(x.extras or {})do if e.type=='ceiling_neon' then e.color={0.05,0.15,1.0};e.emit=3;e.amp=0.45 end end
 add(x,{type='ceiling_neon',rect={-5.2,1.0,-1.6,4.6},amp=0.35,waves=0.9,drop=0.5,color={0.05,0.15,1.0},emit=3})
 add(x,{type='lollipop',at={{-5.7,5.7},{-0.95,5.7}},r=0.55,mat={color={0.1,0.55,0.25},rough=0.3}})
 -- round 11: the coral sofas read pastel pink under the blue neon; a deeper orange-red keeps the photo's coral
 for _,s in ipairs(x.living and x.living.seats or {})do s.mat={color={0.78,0.22,0.1},rough=0.8} end
end
-- 506 愛麗斯派對: round 13 the white large tile still clipped to white under the gold cove (photo: cream-beige tile)
P7['wego-linsen-81a03257f229']=function(x)
 x.floor='marble_cream'
end
-- 306 海洋之心: white backlit square grid behind the bed (the blue-white checker read as a chessboard)
P7['imore-6c3a31ea70b8']=function(x)
 for _,w in ipairs(x.walls or {})do if w.side=='rear' and type(w.mat)=='table' and w.mat.gen and w.mat.gen.kind=='check' then w.mat.gen.bg={0.97,0.97,1.0};w.mat.gen.fg={0.5,0.55,0.68};w.mat.emit=1.2 end end
end
-- 201 Swimming Pool Suite5: lighter blue-teal water (read deep navy)
P7['imore-281de587d726']=function(x)
 if x.pool then x.pool.water={color={0.02,0.13,0.2},opacity=0.55} end
end
-- 311 溫馨雅閣: denser ivy on the arcade; the arcade camera now stands at the entry looking in (photo 2), not back at the door
P7['imore-4994f3264339']=function(x)
 for _,e in ipairs(x.extras or {})do if e.type=='vine_arcade' then e.leaves=20;e.flowers=4;e.trail=true;e.garland_step=0.16 end end
 -- round 10: at fov 72 only the piers showed; wider and tilted up so the ribs read as a tunnel
 view(x,{id='v-entry-arcade',eye={4.41,-10.1,1.5},target={4.41,-4.0,2.3},fov=90})
end
local n=0
for b=1,10 do
 local name=string.format('batch-%02d',b);local cur=dir..name..'.json';local bak=dir..name..'.before-fidelity-v4.json'
 if read(cur)then
  if not read(bak)then write(bak,read(cur))end
  local doc=j.decode(read(bak))
  for _,x in ipairs(doc.rooms)do if P[x.id]then P[x.id](x);n=n+1;print('patched',x.id,x.name)end;if P5[x.id]then P5[x.id](x);n=n+1;print('patched5',x.id,x.name)end;if P6[x.id]then P6[x.id](x);n=n+1;print('patched6',x.id,x.name)end;if P7[x.id]then P7[x.id](x);n=n+1;print('patched7',x.id,x.name)end end
  if not dry then write(cur,j.encode(doc,{indent=1,ensure_ascii=false}))end
 end
end
print('FIDELITY V4',n,'rooms',dry and '(dry)' or '')
