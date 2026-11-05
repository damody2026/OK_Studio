-- Read public source pages; retain per-room identities and reference image URLs.
local code=[====[
import requests,json,re,hashlib,time
from pathlib import Path
from bs4 import BeautifulSoup
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urljoin,urlparse,parse_qs
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');O.mkdir(exist_ok=True);(O/'references').mkdir(exist_ok=True)
def fetch(url):
 for retry in range(3):
  try:
   r=requests.get(url,timeout=45);r.raise_for_status();r.encoding='utf-8';return r.text
  except Exception:
   if retry==2:raise
   time.sleep(2)
def soup(url):return BeautifulSoup(fetch(url),'html.parser')
menu=soup('https://www.imore-motel.com.tw/?page_id=258');nav=menu.select_one('#menu-main-menu') or menu.select_one('nav') or menu
allowed={205,207,221,223,225,227,229,215,231,233,237,239,241,243,245,247,249,251,253,258,260,262,1338,1340,1342,1344}
imore={}
for a in menu.select('a[href]'):
 u=urljoin('https://www.imore-motel.com.tw/',a['href']);pid=parse_qs(urlparse(u).query).get('page_id',[''])[0]
 if pid.isdigit() and int(pid) in allowed:imore[u]=dict(source='imore',name=a.get_text(' ',strip=True),url=u,source_id=pid)
assert len(imore)==26
wego={};listings=[]
for page in range(1,9):
 u='https://linsen.we-go.com.tw/room/'+('?page='+str(page) if page>1 else '');b=soup(u);current=[]
 for h in b.select('a[href]'):
  n=h.get_text(' ',strip=True);v=urljoin(u,h['href'])
  if '/room-detail/' in v and n:current.append(dict(source='wego-linsen',name=n,url=v,source_id=v.rstrip('/').split('/')[-1]))
 listings.append(dict(page=page,url=u,room_urls=[v['url'] for v in current]))
 before=len(wego)
 for q in current:wego[q['url']]=q
 if page>=7 and len(wego)==before:break
for a in soup('https://linsen.we-go.com.tw/room/').select('a[href]'):
 u=urljoin('https://linsen.we-go.com.tw/room/',a['href'])
 if '/room/' in u and u.rstrip('/')!='https://linsen.we-go.com.tw/room':
  for h in soup(u).select('a[href]'):
   v=urljoin(u,h['href']);n=h.get_text(' ',strip=True)
   if '/room-detail/' in v and n:wego[v]=dict(source='wego-linsen',name=n,url=v,source_id=v.rstrip('/').split('/')[-1])
assert len(wego)>=30,('Unexpected incomplete WeGo index',len(wego))
rows=list(imore.values())+list(wego.values())
def detail(q):
 key=q['source']+'-'+hashlib.sha256(q['url'].encode()).hexdigest()[:12];cache=O/'references'/(key+'.html');text=cache.read_text('utf8') if cache.is_file() else fetch(q['url']);b=BeautifulSoup(text,'html.parser');(O/'references'/(key+'.html')).write_text(text,'utf8')
 main=b.select_one('.entry-content') or b.select_one('main') or b
 images=[]
 for tag in main.select('img.ewic-wid-imgs' if q['source']=='imore' else 'img[src*="catalog_room_b"], img[src*="catalog_room_s"]'):
  u=tag.get('data-src') or tag.get('src')
  if u and not u.startswith('data:'):
   u=urljoin(q['url'],u)
   if not any(w in u.lower() for w in ['logo','icon','arrow','global','footer','qrcode']):images.append(dict(url=u,alt=tag.get('alt','')))
 for a in main.select('a[href]'):
  u=urljoin(q['url'],a['href'])
  if re.search(r'\.(jpg|png|webp)(?:\?|$)',u,re.I) and (q['source']=='imore' or 'catalog_room_b/' in u):images.append(dict(url=u,alt=a.get_text(' ',strip=True)))
 unique={i['url']:i for i in images};q.update(id=key,reference_html='references/'+key+'.html',html_sha256=hashlib.sha256(text.encode()).hexdigest(),images=list(unique.values()),page_text=main.get_text(' ',strip=True),status='reference_collected_requires_visual_design_review');return q
done=list(ThreadPoolExecutor(max_workers=4).map(detail,rows));(O/'reference-catalog.json').write_text(json.dumps(dict(status='references_collected_not_models',collected_at=time.strftime('%Y-%m-%dT%H:%M:%S')+'+08:00',rooms=done,listings=listings,scope='Public referenced room pages; distinct URL variants retained even when names repeat. Photo URLs are reference evidence, not imported scene textures.'),ensure_ascii=False,indent=2),'utf8')
print('Collected',len(imore),'iMore room types and',len(wego),'distinct WeGo room-detail URLs;',len(done),'total. Modeling and visual acceptance pending.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
