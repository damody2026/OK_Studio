local f=assert(io.open('Tools/inspect_street_city_water_deck.lua','rb'));local s=f:read('*a');f:close();local code=assert(s:match('local code=%[====%[(.-)%]====%]'))
code=code:gsub('World_PK_0105','World_PK_0101'):gsub('%[1,5%]','[0,3]'):gsub('water%-deck%-geometry.json','plaza-roof-geometry.json')
code=code..[=[
rv=v[np.unique(tri[slots==3])];print('LOW ROOF VERTICES',rv[rv[:,2]<1600].round(3).tolist())
for x,y in [(54570,69670),(55030,69670),(54570,70330),(55030,70330)]:
 hits=[]
 for t,s in zip(tri,slots):
  if s!=3:continue
  a,b,c=v[t];mat=np.array([[b[0]-a[0],c[0]-a[0]],[b[1]-a[1],c[1]-a[1]]]);det=np.linalg.det(mat)
  if abs(det)<.001:continue
  u,w=np.linalg.solve(mat,np.array([x-a[0],y-a[1]]))
  if u>=-.00001 and w>=-.00001 and u+w<=1.00001:hits.append(float(a[2]+u*(b[2]-a[2])+w*(c[2]-a[2])))
 print('POST TOP',x,y,1597.1223908818356,'ROOF FACES',sorted(set(round(z,3) for z in hits)))
]=]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
