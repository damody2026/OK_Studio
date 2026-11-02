-- Dead road ends from the 2 m road raster (native job world_road_raster_probe -> world-edge-v1/road-raster.json).
-- A road cell is an end candidate when, on a 10 m circle around it, the road cells form one arc narrower than 140 degrees
-- (one way out) and the opposite side 4-8 m away is grass ('g'), so roads that stop at water, buildings, paving or the
-- city edge are not ends. Candidates within 20 m are merged; each end gets the outward direction (opposite of the arc
-- centre), the road width measured across the road 8 m back, and the end point where the road mask stops on that axis.
-- Street ends (>= 8 m wide) with another street within 100 m ahead become road connectors, the rest turning circles.
-- Output world-edge-v1/road-ends.json (read by world_road_ends_install).
-- Usage: lua Tools/find_street_city_road_ends.lua
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local dir='output/street-social-city-production/world-edge-v1/'
local f=assert(io.open(dir..'road-raster.json','rb'));local R=j.decode(f:read('a'));f:close()
local S=R.step_cm;local ox,oy=R.origin[1],R.origin[2];local rows=R.rows;local NY=#rows;local NX=#rows[1]
local function at(k,i)if i<1 or i>NY or k<1 or k>NX then return nil end return rows[i]:sub(k,k) end
local function atw(x,y)return at(math.floor((x-ox)/S+.5)+1,math.floor((y-oy)/S+.5)+1)end
local N=72;local cand={}
for i=1,NY do for k=1,NX do if at(k,i)=='r' then
 local x,y=ox+(k-1)*S,oy+(i-1)*S;local ring={};local out=false
 for a=0,N-1 do local t=a*2*math.pi/N;local c=atw(x+1000*math.cos(t),y+1000*math.sin(t));if c==nil then out=true end;ring[a]=(c=='r' or c==nil) end
 if not out then
  local arcs,start=0,nil
  for a=0,N-1 do if ring[a] and not ring[(a-1)%N] then arcs=arcs+1;start=a end end
  if arcs==1 then
   local w,sx,sy=0,0,0;local a=start
   while ring[a%N] and w<N do local t=(a%N)*2*math.pi/N;sx=sx+math.cos(t);sy=sy+math.sin(t);w=w+1;a=a+1 end
   if w*360/N<140 then
    local L=math.sqrt(sx*sx+sy*sy);local ux,uy=-sx/L,-sy/L
    local grass=true;for _,d in ipairs({400,600,800})do if atw(x+ux*d,y+uy*d)~='g' then grass=false end end
    if grass then cand[#cand+1]={x=x,y=y,ux=ux,uy=uy} end
   end
  end
 end
end end end
local ends={}
for _,c in ipairs(cand)do
 local g;for _,e in ipairs(ends)do if math.sqrt((e.sx/e.n-c.x)^2+(e.sy/e.n-c.y)^2)<2000 then g=e break end end
 if not g then g={n=0,sx=0,sy=0,ux=0,uy=0};ends[#ends+1]=g end
 g.n=g.n+1;g.sx=g.sx+c.x;g.sy=g.sy+c.y;g.ux=g.ux+c.ux;g.uy=g.uy+c.uy
end
local out={}
for _,e in ipairs(ends)do
 local cx,cy=e.sx/e.n,e.sy/e.n;local L=math.sqrt(e.ux^2+e.uy^2);local ux,uy=e.ux/L,e.uy/L;local vx,vy=-uy,ux
 -- road run across the axis at `back` cm behind the cluster centre: its centre and width
 local function across(back)
  local bx,by=cx-ux*back,cy-uy*back;local lo,hi=0,0
  if atw(bx,by)~='r' then return nil end
  while atw(bx+vx*(lo-S),by+vy*(lo-S))=='r' and lo>-4000 do lo=lo-S end
  while atw(bx+vx*(hi+S),by+vy*(hi+S))=='r' and hi<4000 do hi=hi+S end
  return bx+vx*(lo+hi)/2,by+vy*(lo+hi)/2,hi-lo+S
 end
 local ax,ay,w8=across(800);local _,_,w16=across(1600);local _,_,w30=across(3000)
 -- a real end is a straight road stub: the same width 8, 16 and 30 m back (an L corner or a junction measures one arm
 -- lengthwise) and no wider than a street
 if ax and w16 and w30 and math.abs(w8-w16)<=400 and math.abs(w8-w30)<=400 and w8<=2400 then
 -- the arc centre is only rough: the stub axis runs through the road centres 30 and 8 m back
 local bx,by=across(3000);local L2=math.sqrt((ax-bx)^2+(ay-by)^2)
 if L2>100 then ux,uy=(ax-bx)/L2,(ay-by)/L2;vx,vy=-uy,ux end
 -- walk out along the axis to the last road cell
 local d=0;while atw(ax+ux*(d+S/2),ay+uy*(d+S/2))=='r' and d<6000 do d=d+S/2 end
 local ex,ey=ax+ux*d,ay+uy*d
 -- street ends only (footpaths stop where they like); a gap of at most 100 m to another street ahead is closed with a
 -- road strip (the bridge stub over the river, the south road), anything else gets a turning circle
 if w8>=800 then
  local gap
  for t=S,10000,S/2 do
   if atw(ex+ux*t,ey+uy*t)=='r' then
    local hx,hy=ex+ux*t,ey+uy*t;local n=0
    for q=-3000,3000,S do if atw(hx+vx*q,hy+vy*q)=='r' then n=n+1 end end
    if n*S>=800 then gap=t break end
   end
  end
  out[#out+1]={kind=gap and 'connector' or 'circle',x=math.floor(ex+.5),y=math.floor(ey+.5),z=1205,dir={ux,uy},width=w8,length=gap,candidates=e.n}
 end
 end
end
-- two ends closing the same gap from both sides keep one connector
local keep={}
for i,e in ipairs(out)do
 local dup=false
 if e.kind=='connector' then for k=1,i-1 do local o=out[k];if o.kind=='connector' and math.abs(o.length-e.length)<1500 and math.sqrt((o.x+o.dir[1]*o.length-e.x)^2+(o.y+o.dir[2]*o.length-e.y)^2)<2000 then dup=true end end end
 if not dup then keep[#keep+1]=e end
end
out=keep
-- two street ends within 100 m that face each other (the river bridge stub sits beside the ring road end and the south
-- road gap) are joined end to end; such an end needs no turning circle
local pairs_={}
for a=1,#out do for b=a+1,#out do
 local A,B=out[a],out[b];local dx,dy=B.x-A.x,B.y-A.y;local d=math.sqrt(dx*dx+dy*dy)
 if d<=10000 and d>0 and (A.dir[1]*dx+A.dir[2]*dy)/d>.2 and -(B.dir[1]*dx+B.dir[2]*dy)/d>.2 then
  pairs_[#pairs_+1]={kind='link',x=A.x,y=A.y,z=1205,to={B.x,B.y},width=math.min(A.width,B.width),length=d};A.linked=true;B.linked=true
 end
end end
local final={}
for _,e in ipairs(out)do if e.kind=='connector' or not e.linked then final[#final+1]=e end end
for _,l in ipairs(pairs_)do final[#final+1]=l end
out=final
for _,e in ipairs(out)do print(('%s x %.0f y %.0f width %.0f cm%s'):format(e.kind,e.x,e.y,e.width,e.to and (' to '..e.to[1]..','..e.to[2]) or e.length and (' gap '..e.length..' cm') or ''))end
local f=assert(io.open(dir..'road-ends.json','wb'));f:write(j.encode({status='derived',map_sha256=R.map_sha256,source='road-raster.json',ends=out}));f:close()
print(#out..' street ends')
