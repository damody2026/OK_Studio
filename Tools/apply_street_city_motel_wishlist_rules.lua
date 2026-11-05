-- Turn each motel room's tripo_wishlist / photo_notes into procedural spec changes (no Tripo generation):
-- seat kinds, headboards, canopies, signature pieces (heart booth, swing bed, lanterns, arch mirror, folding screen),
-- drum tables and tub variants. Idempotent; the first run keeps room-specs/batch-NN.before-wishlist.json.
-- Usage: lua Tools/apply_street_city_motel_wishlist_rules.lua [--dry]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json')
local dir='output/street-social-city-production/motel-v1/room-specs/'
local dry=arg[1]=='--dry'
local function has(s,...)for _,k in ipairs({...})do if not s:find(k,1,true)then return false end end;return true end
local function any(s,...)for _,k in ipairs({...})do if s:find(k,1,true)then return true end end;return false end
local function hasextra(x,t)for _,e in ipairs(x.extras or {})do if e.type==t then return true end end;return false end
local SOFA={modern=true,curved=true}
local log={}
local function note(x,msg)log[#log+1]=x.name..'：'..msg end
local function rules(x)
 local wish=table.concat(x.tripo_wishlist or {},'、');local notes=x.photo_notes or ''
 local lv=x.living or {};x.living=lv;local seats=lv.seats or {};lv.seats=seats;local bed=x.bed or {};x.bed=bed;local hb=bed.headboard or {};bed.headboard=hb
 x.extras=x.extras or {};x.bath=x.bath or {};x.chandeliers=x.chandeliers or {}
 for _,e in ipairs(x.extras)do if e.mat=='gold_leaf' then e.mat={color={0.85,0.65,0.25},metal=0.8,rough=0.35} end end  -- earlier rule used a non-existent preset
 -- seats
 if seats[1] and SOFA[seats[1].kind or 'modern'] then
  if any(wish,'切斯特菲爾德','捲扶手')then seats[1].kind='chesterfield';note(x,'沙發改切斯特菲爾德')
  elseif has(wish,'巴洛克')and any(wish,'沙發','貴妃椅')then seats[1].kind='baroque';note(x,'沙發改巴洛克') end
 end
 if any(wish,'翼椅','翼沙發')then
  for k=2,#seats do if not ({baroque=1,chesterfield=1,modern=1,curved=1})[seats[k].kind or 'modern'] and seats[k].kind~='wing' then seats[k].kind='wing';note(x,'單椅改高背翼椅');break end end
 end
 -- bed
 if has(wish,'四柱床')and not bed.canopy then
  local c=any(wish,'紅布幔','紅')and {0.55,0.05,0.06} or (any(wish,'黑蕾絲','黑')and {0.04,0.03,0.04}) or {0.92,0.88,0.8}
  bed.canopy={drape={color=c,rough=0.85,alpha=0.75}};note(x,'加四柱床幔')
 end
 local ptype=hb.type or 'panel'
 if has(wish,'愛心')and has(wish,'床頭')then if ptype~='heart' or hb.mat=='velvet_tufted_red' then hb.type='heart';hb.mat={color={0.8,0.05,0.12},rough=0.5};note(x,'床頭改愛心軟包') end
 elseif has(wish,'扇形床頭')then if ptype~='round_pleat' then hb.type='round_pleat';note(x,'床頭改扇形') end
 elseif ptype=='panel' and has(wish,'床頭')and any(wish,'菱格','方格','鑽扣','軟包')then hb.type='tufted';note(x,'床頭改軟包')
 elseif ptype=='panel' and has(wish,'雕花')and has(wish,'床頭')then hb.type='crown';note(x,'床頭改雕花')
 end
 -- signature pieces
 if has(wish,'鞦韆床')and not hasextra(x,'swing_bed')then
  local keep={};for _,e in ipairs(x.extras)do if e.type~='swing' then keep[#keep+1]=e end end;x.extras=keep
  x.extras[#x.extras+1]={type='swing_bed',vines=any(wish,'藤','玫瑰')};note(x,'加鞦韆床')
 end
 -- the heart booth is the room's main sofa in the photos: it takes the first seat's place
 if has(wish,'卡座')and has(wish,'愛心')and seats[1] and seats[1].kind~='heart_booth' then
  local keep={};for _,e in ipairs(x.extras)do if e.type~='heart_booth' then keep[#keep+1]=e end end;x.extras=keep
  seats[1].kind='heart_booth';note(x,'主沙發改愛心鏤空高背卡座')
 end
 if has(wish,'燈籠')then
  if x.chandeliers[1] then if x.chandeliers[1].kind~='lantern' then x.chandeliers[1].kind='lantern';x.chandeliers[1].key=nil;note(x,'吊燈改燈籠') end
  else x.chandeliers[1]={kind='lantern',at={2.4,-0.5}};note(x,'加燈籠吊燈') end
 end
 if has(wish,'拱門鏡')and not hasextra(x,'arch_mirror')then x.extras[#x.extras+1]={type='arch_mirror',bulbs=has(wish,'燈泡')};note(x,'加拱門鏡') end
 if has(wish,'屏風')and not hasextra(x,'folding_screen')then
  local m=any(wish,'紅')and {color={0.65,0.06,0.05},rough=0.45} or (any(wish,'金')and {color={0.85,0.65,0.25},metal=0.8,rough=0.35} or nil)
  x.extras[#x.extras+1]={type='folding_screen',mat=m};note(x,'加折疊屏風')
 end
 if has(wish,'鼓形')and any(wish,'茶几','底座','圓几')and lv.table and lv.table.kind~='round_drum' then lv.table.kind='round_drum';lv.table.size={1.4,1.4};note(x,'茶几改鼓形') end
 -- bath
 if has(wish,'貓腳浴缸')then if x.bath.tub~='clawfoot' then x.bath.tub='clawfoot';note(x,'浴缸改貓腳') end
 elseif (x.bath.tub or 'rect')=='round' and has(notes,'浴缸')and any(notes,'大理石圓形','石砌','圓形石')then x.bath.tub='platform';note(x,'浴缸改石砌高台')
 elseif any(notes,'獨立浴缸','橢圓浴缸')then x.bath.tub='oval';note(x,'浴缸改橢圓獨立缸') end
 -- underwater light only when the glow word sits right before the tub in the same note (~15 characters)
 local p=1
 while not x.bath.glow do
  local a=notes:find('浴缸',p,true);if not a then break end
  local win=notes:sub(math.max(1,a-45),a)
  if any(win,'發光','紫光','藍光','燈光')then x.bath.glow=any(win,'藍光')and {0.2,0.5,1.0} or {0.85,0.3,1.0};note(x,'浴缸加水中燈') end
  p=a+1
 end
end
for i=1,10 do
 local p=string.format('%sbatch-%02d.json',dir,i);local f=assert(io.open(p,'rb'));local raw=f:read('a');f:close()
 local bk=string.format('%sbatch-%02d.before-wishlist.json',dir,i)
 if not dry and not io.open(bk,'rb')then local g=assert(io.open(bk,'wb'));g:write(raw);g:close()end
 local d=j.decode(raw);for _,x in ipairs(d.rooms)do rules(x)end
 if not dry then local g=assert(io.open(p,'wb'));g:write(j.encode(d));g:close()end
end
for _,l in ipairs(log)do print(l)end
print(#log..' changes'..(dry and ' (dry run)' or ''))
