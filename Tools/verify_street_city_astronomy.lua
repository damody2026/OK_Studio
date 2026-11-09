-- Independent pinned C ephemeris versus public NASA Horizons reference files.
-- This checks the ephemeris, not the UE controller integration.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local out=root..'/output/street-social-city-production/day-night-v1'
local lib=root..'/StreetSocialCity/Plugins/CityEnvironment/Source/ThirdParty/Astronomy'
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
write(out..'/ephemeris-adapter.c',[=[
#include "astronomy.h"
__declspec(dllexport) int evaluate(int y,int m,int d,int hour,int body,double *out){
 astro_time_t t=Astronomy_MakeTime(y,m,d,hour,0,0);
 astro_observer_t observer=Astronomy_MakeObserver(23.5,121,0);
 astro_equatorial_t eq=Astronomy_Equator(body==10?BODY_SUN:BODY_MOON,&t,observer,EQUATOR_OF_DATE,ABERRATION);
 if(eq.status!=ASTRO_SUCCESS)return eq.status;
 astro_horizon_t h=Astronomy_Horizon(&t,observer,eq.ra,eq.dec,REFRACTION_NONE);
 astro_horizon_t apparent=Astronomy_Horizon(&t,observer,eq.ra,eq.dec,REFRACTION_NORMAL);
 out[0]=h.azimuth;out[1]=h.altitude;out[2]=apparent.azimuth;out[3]=apparent.altitude;return 0;
}
__declspec(dllexport) int fullmoon(double *out){
 astro_time_t t=Astronomy_MakeTime(2026,10,21,16,0,0);
 astro_search_result_t s=Astronomy_SearchMoonPhase(180,t,40);
 if(s.status!=ASTRO_SUCCESS)return s.status;
 astro_utc_t u=Astronomy_UtcFromTime(s.time);out[0]=u.year;out[1]=u.month;out[2]=u.day;out[3]=u.hour;out[4]=u.minute;out[5]=u.second;return 0;
}
__declspec(dllexport) int riseset(int y,int m,int d,double *out){
 astro_time_t start=Astronomy_AddDays(Astronomy_MakeTime(y,m,d,0,0,0),-8.0/24);
 astro_observer_t observer=Astronomy_MakeObserver(23.5,121,0);
 astro_search_result_t r=Astronomy_SearchRiseSet(BODY_SUN,observer,DIRECTION_RISE,start,1);
 astro_search_result_t s=Astronomy_SearchRiseSet(BODY_SUN,observer,DIRECTION_SET,start,1);
 if(r.status||s.status)return 1;out[0]=(r.time.ut-start.ut)*24;out[1]=(s.time.ut-start.ut)*24;return 0;
}
]=])
local compile=ok.proc.run({'gcc','-O2','-shared','-I',lib,out..'/ephemeris-adapter.c',lib..'/astronomy.c','-lm','-o',out..'/ephemeris-reference.dll'},{cwd=root,hide=true});assert(compile.code==0,'ephemeris adapter compile failed')
write(out..'/ephemeris-reference-check.txt',[=[
import ctypes,json,re,sys,math,hashlib
from pathlib import Path
from datetime import datetime,timezone,timedelta
folder=Path(sys.argv[1]);lib=ctypes.CDLL(str(folder/'ephemeris-reference.dll'));ptr=ctypes.POINTER(ctypes.c_double)
lib.evaluate.argtypes=[ctypes.c_int]*5+[ptr];lib.evaluate.restype=ctypes.c_int;lib.fullmoon.argtypes=[ptr];lib.fullmoon.restype=ctypes.c_int
lib.riseset.argtypes=[ctypes.c_int]*3+[ptr];lib.riseset.restype=ctypes.c_int
rows=[];sources=[]
for p in sorted((folder/'astronomy-reference').glob('*.json')):
 q=json.loads(p.read_text('utf-8-sig'));text=q['response']['result'];body=10 if re.search(r'Target body name: Sun',text) else 301
 sources.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),url=q.get('url')))
 for line in text.split('$$SOE')[1].split('$$EOE')[0].strip().splitlines():
  cols=[x.strip() for x in line.split(',')];t=datetime.strptime(cols[0],'%Y-%b-%d %H:%M');expected=[float(cols[3]),float(cols[4])];out=(ctypes.c_double*4)();assert lib.evaluate(t.year,t.month,t.day,t.hour,body,out)==0
  az=abs((out[0]-expected[0]+180)%360-180);alt=abs(out[1]-expected[1]);a,b=map(math.radians,[out[1],expected[1]]);angular=math.degrees(math.acos(max(-1,min(1,math.sin(a)*math.sin(b)+math.cos(a)*math.cos(b)*math.cos(math.radians(az))))))
  rows.append(dict(utc=t.isoformat(),body=body,expected_az_alt=expected,actual_az_alt=list(out)[:2],apparent_normal_az_alt=list(out)[2:],az_error_degrees=az,alt_error_degrees=alt,angular_error_degrees=angular,above_5_degrees=expected[1]>5))
assert len(rows)==200,len(rows)
above=[q for q in rows if q['above_5_degrees']];worst=max(q['angular_error_degrees'] for q in above);assert worst<=.25,worst
out=(ctypes.c_double*6)();assert lib.fullmoon(out)==0;y,m,d,h,mi=[int(x) for x in out[:5]];full=datetime(y,m,d,h,mi,int(out[5]),tzinfo=timezone.utc).astimezone(timezone(timedelta(hours=8)))
rise_rows=[]
for month,day in [(3,20),(6,21),(9,23),(12,21)]:
 out=(ctypes.c_double*2)();assert lib.riseset(2026,month,day,out)==0;rise_rows.append(dict(date=f'2026-{month:02}-{day:02}',sunrise_local_hours=out[0],sunset_local_hours=out[1]))
result=dict(status='passed',scope='Pinned Astronomy Engine C only; UE runtime still requires independent integration checks',convention='topocentric, equator of date, aberration, airless; NASA Horizons apparent AIRLESS',samples=len(rows),above_5_samples=len(above),max_angular_error_degrees=worst,full_moon_local=full.isoformat(),sources=sources,rows=rows,rise_set=rise_rows)
(folder/'ephemeris-reference-check.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),'utf8');print(json.dumps({k:v for k,v in result.items() if k not in ['rows','sources']}))
]=])
local result=ok.proc.run({'python','-c','from pathlib import Path;import sys;code=Path(sys.argv.pop(1)).read_text();exec(code);',out..'/ephemeris-reference-check.txt',out},{cwd=root,hide=true})
assert(result.code==0,'ephemeris verification failed')
