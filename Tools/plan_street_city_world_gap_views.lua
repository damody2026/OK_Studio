-- Whole-world visual gap inventory: camera plan from world-gap-v1/outdoor-scan.json (Tools/street_city_world_gap_payload.lua).
--   ground views: one per 90 m cell, at the walkable ground point with the fewest small actors within 12 m (the emptiest
--     spot of the cell), eye 1.65 m, heading rotates N/E/S/W by cell so neighbouring cells look different ways.
--     A point more than 3 m above the lowest walkable ground within 90 m is a roof or deck and is skipped.
--   aerial views: one per 300 m cell with any walkable ground, 90 m up, 45 deg down toward the cell centre.
-- Output: world-gap-v1/gap-views.json ([{id,eye,target,fov,hour}] world cm, for capture_street_city_shop_survey.lua --views)
--         world-gap-v1/gap-cells.json (per 90 m cell: walkable points, mean small-actor count, top prefixes)
-- Usage: lua Tools/plan_street_city_world_gap_views.lua
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json')
local dir='output/street-social-city-production/world-gap-v1/'
local function read(p)local f=assert(io.open(p,'rb'));local r=f:read('a');f:close();return r end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local scan=j.decode(read(dir..'outdoor-scan.json'))
-- '--bbox x0 x1 y0 y1' (cm): keep only points inside, for scans made before the payload bounded the grid by the buildings
local bb=arg[1]=='--bbox' and {tonumber(arg[2]),tonumber(arg[3]),tonumber(arg[4]),tonumber(arg[5])} or nil
local pts={}
for _,p in ipairs(scan.points)do if p.walk and (not bb or (p.x>=bb[1] and p.x<=bb[2] and p.y>=bb[3] and p.y<=bb[4])) then pts[#pts+1]=p end end
-- lowest walkable ground near each point (buckets of 90 m)
local B=9000;local low={}
local function key(x,y,s)return math.floor(x/s)..':'..math.floor(y/s)end
for _,p in ipairs(pts)do local k=key(p.x,p.y,B);low[k]=math.min(low[k] or 1e9,p.z)end
local function lowest(x,y)local m=1e9;for dx=-1,1 do for dy=-1,1 do local v=low[key(x+dx*B,y+dy*B,B)];if v and v<m then m=v end end end;return m end
local cells,order={},{}
for _,p in ipairs(pts)do
 if p.z<=lowest(p.x,p.y)+300 then
  local n=0;for _,c in pairs(p.near or {})do n=n+c end;p.n=n
  local k=key(p.x,p.y,B);if not cells[k]then cells[k]={i=math.floor(p.x/B),k=math.floor(p.y/B),pts={}};order[#order+1]=k end
  table.insert(cells[k].pts,p)
 end
end
table.sort(order,function(a,b)local A,C=cells[a],cells[b];return A.i<C.i or (A.i==C.i and A.k<C.k)end)
local views,rows=j.array({}),j.array({})
local H={{1,0},{0,1},{-1,0},{0,-1}}
for idx,k in ipairs(order)do
 local c=cells[k];table.sort(c.pts,function(a,b)return a.n<b.n or (a.n==b.n and (a.x+a.y)<(b.x+b.y))end)
 local tot,pre=0,{};for _,p in ipairs(c.pts)do tot=tot+p.n;for q,m in pairs(p.near or {})do pre[q]=(pre[q] or 0)+m end end
 local tops={};for q,m in pairs(pre)do tops[#tops+1]={q,m}end;table.sort(tops,function(a,b)return a[2]>b[2]end)
 local tp=j.array({});for i=1,math.min(5,#tops)do tp[#tp+1]=tops[i][1]..'='..tops[i][2]end
 local p=c.pts[1];local h=H[(c.i+c.k)%4+1];local id=string.format('G%03d',idx)
 views[#views+1]={id=id,eye={p.x,p.y,p.z+165},target={p.x+h[1]*2500,p.y+h[2]*2500,p.z+120},fov=90,hour=15}
 rows[#rows+1]={id=id,cell={c.i,c.k},walkable=#c.pts,mean_near=tot/#c.pts,emptiest={p.x,p.y,p.z},emptiest_near=p.n,ground=p.ground_prefix,mat=p.mat,top_prefixes=tp}
end
-- aerial: 300 m cells
local A=30000;local ac,ao={}, {}
for _,k in ipairs(order)do for _,p in ipairs(cells[k].pts)do local q=key(p.x,p.y,A);if not ac[q]then ac[q]={sx=0,sy=0,sz=0,n=0};ao[#ao+1]=q end;local a=ac[q];a.sx=a.sx+p.x;a.sy=a.sy+p.y;a.sz=a.sz+p.z;a.n=a.n+1 end end
table.sort(ao)
for i,q in ipairs(ao)do
 local a=ac[q];local x,y,z=a.sx/a.n,a.sy/a.n,a.sz/a.n
 if a.n>=4 then views[#views+1]={id=string.format('A%02d',i),eye={x-9000,y,z+9000},target={x,y,z},fov=80,hour=15}end
end
write(dir..'gap-views.json',j.encode(views,{indent=1}))
write(dir..'gap-cells.json',j.encode({map_sha256=scan.map_sha256,cells=rows},{indent=1}))
local g,a=0,0;for _,v in ipairs(views)do if v.id:sub(1,1)=='G' then g=g+1 else a=a+1 end end
print('GAP VIEWS ground',g,'aerial',a,'walkable points',#pts)
