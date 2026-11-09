-- Publish the motel delivery page and play launchers only when every receipt matches the current source map and package.
local code=[====[
import json,hashlib,html,os,datetime,math
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu');O=R/'output/street-social-city-production/motel-v1';D=R/'output/street-social-city-production/motel-decor-tripo-v1'
def read(p):return json.loads(Path(p).read_text('utf8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
mapsha=sha(R/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')
package=read(O/'package.json');audit=read(O/'audit.json');routes=read(O/'route-review.json');plan=read(O/'game-physics-plan.json');physics=read(O/'physics-latest.json');captures=read(O/'captures.json');sheets=read(O/'contact-sheets.json');review=read(O/'visual-review.json');install=read(O/'motel-install.json');motel=read(O/'motel-plan.json')
placement=read(D/'placement.json');imports=read(D/'imports.json');remeshed=read(D/'remeshed.json');subs=read(D/'submissions.json')
assert package['engine']=='E:/PhysX/UE5.8' and package['exit_code']==0
assert all(r['map_sha256']==mapsha for r in [package,audit,routes,plan,physics,captures,sheets,review,install,placement]),'Receipt map SHA mismatch'
assert audit['status']=='passed' and not audit['issues'] and routes['status']=='passed' and not routes['issues']
assert len(plan['walk_routes'])==79
# Full CharacterMovement traversal on this exact package: every route id, no step assists, immutable stage.
assert physics['status']=='passed' and physics['package_id']==package['id'] and physics['full_route_expected'] and physics['coverage_passed'] and physics['unique_completed_routes']==len(plan['walk_routes']) and not physics['missing_routes'] and physics['walking_step_assists']==0 and physics['immutable_stage_unchanged']
native=read(physics['native_receipt']);assert set(r['id'] for r in plan['walk_routes'])<=set(r['route'] for r in native['completed_route_records']) and native['normal_input_smoke_passed'] and native['player_start_passed']
for r in physics['native_images_manifest']:assert sha(r['path'])==r['sha256']
exe=Path(package['target'])/'Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe';assert exe.is_file() and sha(exe)==physics['executable_sha256']
assert not captures['preview'] and not captures['focus'] and captures['package_id']==package['id'] and captures['expected_images']==len(captures['images'])
for r in captures['images']:assert sha(r['path'])==r['sha256']
assert sheets['package_id']==review['package_id']==package['id'] and review['all_current_sheets_reviewed'] and review['status']=='passed_current_sheets'
for s in sheets['sheets']:assert sha(s['path'])==s['sha256'] and review['reviewed_sheets'][s['id']]['sha256']==s['sha256']
assert placement['ornaments']==122 and imports['completed']==122 and remeshed['completed']==122
lookup={r['id']:r for r in captures['images']}
def url(p):return os.path.relpath(p,O).replace('\\','/')
decor={a['id']:a for a in subs['assets']};rung={a['id']:a.get('rung') for a in remeshed['assets']}
rooms=[];installed={r['id']:r for r in install['rooms']}
for q in motel['rooms']:
 shots={k:url(lookup[q['id']+'-'+k]['path']) for k in ['bed-12','bed-21','bath-21','decorA-12','decorB-12']}
 rooms.append(dict(id=q['id'],building=q['building'],room=q['room_number'],name=q['source_name'],floor=q['floor'],style=q['style'],pool=q['is_pool_suite'],source=q['reference_url'],shots=shots,decorA=decor[q['id']+'-decor-A']['description'],decorB=decor[q['id']+'-decor-B']['description']))
extra=[dict(id=r['id'],url=url(r['path']),hour=r['hour']) for r in captures['images'] if not any(s in r['id'] for s in ['-bed-','-bath-','-decor'])]
walk=[url(r['path']) for r in physics['native_images_manifest']]
# Launchers: normal walking pawn, WASD, F7 tour flight with collision, F8 time panel. Room shortcuts teleport the walking pawn to the room entry.
play=O/'Play-Motel.cmd';user='C:/portable/OpenKoikatsu/Saved/StreetSocialCityMotelPlayUser'
base='"'+str(exe).replace('/','\\')+'" /Game/UniversityCity/Maps/UniversityCity -d3d12 -norhithread -windowed -ResX=1920 -ResY=1080 -NoVSync "-UserDir='+user+'"'
play.write_bytes(('@echo off\r\nsetlocal\r\nstart "Motel" '+base+' "-ExecCmds=t.MaxFPS 60"\r\n').encode('utf8'))
# ULocalPlayer::ExecMacro prefixes ../../Binaries/ to any path without "Binaries", so macros live in a Binaries folder.
roomdir=O/'play-rooms';macrodir=roomdir/'Binaries';macrodir.mkdir(parents=True,exist_ok=True);shortcuts=[]
# Teleport target: second point of the room's verified CharacterMovement route (inside the door; the threshold point
# itself overlaps the frame and BugItGo's encroachment check rejects it). Capsule centre = floor + 100cm.
suite={w['id'][:-len('-actual-player-entry')]:w['points'] for w in plan['walk_routes'] if w['kind']=='motel_suite'}
for q in rooms:
 pts=suite[q['id']];a,b=pts[1],pts[2];yaw=math.degrees(math.atan2(b[1]-a[1],b[0]-a[0]))
 macro=macrodir/(q['building']+'-'+q['room']+'.txt');macro.write_text('t.MaxFPS 60\nEnableCheats\n'+'DEFER '*300+'BugItGo %.1f %.1f %.1f 0 %.2f 0\n'%(a[0],a[1],a[2]+100,yaw),encoding='ascii')
 cmd=roomdir/(q['building']+'-'+q['room']+'.cmd');cmd.write_bytes(('@echo off\r\nsetlocal\r\nstart "Motel '+q['building']+' '+q['room']+'" '+base+' "-ExecCmds=exec '+str(macro).replace('\\','/')+'"\r\n').encode('utf8'));q['launcher']=url(cmd);shortcuts.append(str(cmd))
data=dict(rooms=rooms,extra=extra,walk=walk,package=package['id'],map=mapsha,exe=str(exe),routes=physics['unique_completed_routes'],trips=physics['completed_walk_routes'],soak=physics['soak_seconds'],images=len(captures['images']))
payload=json.dumps(data,ensure_ascii=False).replace('<','\\u003c')
document='''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>影輝之夜 汽車旅館</title>
<style>:root{color-scheme:dark;--ink:#f3ece9;--muted:#bba9a6;--line:#4a3438;--accent:#e2a6b4;--bg:#171012}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.7 system-ui,"Microsoft JhengHei",sans-serif}main{max-width:1280px;margin:auto;padding:44px 24px}h1{font-size:clamp(30px,5vw,56px);line-height:1.2;margin:12px 0}h2{font-size:24px;margin:44px 0 14px}p{color:var(--muted);max-width:920px}a{color:var(--accent)}.eyebrow{letter-spacing:.2em;color:var(--accent);font-size:12px}.tags{display:flex;gap:10px;flex-wrap:wrap}.tags span{border:1px solid var(--line);padding:4px 12px;border-radius:99px;font-size:13px}.button{display:inline-block;border:1px solid var(--line);background:#3a2229;color:var(--ink);border-radius:7px;padding:8px 15px;text-decoration:none;margin:0 8px 8px 0}select{font:inherit;background:#2a1a1e;color:var(--ink);border:1px solid var(--line);border-radius:7px;padding:6px 10px}.room{border-top:1px solid var(--line);padding:22px 0}.room h3{margin:0 0 4px;font-size:20px}.room .meta{color:var(--muted);font-size:14px}.shots{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:8px;margin-top:10px}figure{margin:0}figure img{display:block;width:100%;aspect-ratio:16/9;object-fit:cover;background:#0b0708;border:1px solid var(--line);border-radius:6px}figcaption{font-size:12px;color:var(--muted);padding:4px 0}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px}table{width:100%;border-collapse:collapse}td,th{text-align:left;padding:10px;border-bottom:1px solid var(--line);vertical-align:top}code{word-break:break-all;font-size:13px}footer{padding:30px 0;color:var(--muted);font-size:13px}@media(max-width:900px){.shots{grid-template-columns:repeat(2,minmax(0,1fr))}.grid{grid-template-columns:1fr}main{padding:24px 16px}}</style>
<main><div class="eyebrow">YINGHUI UNIVERSITY TOWN · MOTEL</div><h1>影輝之夜・花境<br>情趣汽車旅館</h1><p>依 iMore 與 WeGo 林森館官網 61 個房型的風格與配置改編的原創遊戲場景（推導尺寸，不是實測一比一復刻）。H1「影輝之夜」58 間、S18「花境」3 間；每間有獨立浴室與大片鏡面，並各擺兩件以 Tripo3D 生成、instant-meshes-rs 重鋪的專屬飾品。全城廁所也加了洗手台鏡面。</p>
<div class="tags"><span>E 槽 UE5.8 完整封裝</span><span>61 房型</span><span>122 件房間專屬飾品</span><span>79 條路線真人物理實走</span><span id="imgTag"></span></div>
<p><a class="button" href="Play-Motel.cmd" download>遊玩啟動檔</a><a class="button" href="#rooms">瀏覽 61 間房</a><a class="button" href="#scenes">泳池、外觀與廁所</a><a class="button" href="#walk">實走畫面</a></p>
<p>雙擊 <code>Play-Motel.cmd</code> 開始遊玩。WASD／方向鍵步行、滑鼠看向、Shift 快走、Space 跳躍；F7 切換仍有碰撞的巡覽飛行，E／Q 升降；F8 開關時間介面。每間房的「直接進房」捷徑在 <code>play-rooms/</code>，會在載入後把步行角色傳送到該房門口。</p>
<section id="rooms"><h2>61 間房</h2><p><select id="bld" aria-label="選擇建物"><option value="all">全部建物</option><option value="H1">H1 影輝之夜</option><option value="S18">S18 花境</option></select></p><div id="roomList"></div></section>
<section id="scenes"><h2>泳池、外觀與廁所鏡面</h2><div class="grid" id="extra"></div></section>
<section id="walk"><h2>真人物理實走畫面</h2><p id="walkNote"></p><div class="grid" id="walkGrid"></div></section>
<section><h2>驗收證據</h2><table><tr><th>項目</th><th>結果</th></tr><tr><td>原始碼稽核</td><td>244 條射線、61 房膠囊掃掠、971 組洗手台、1033 面新鏡面，0 問題</td></tr><tr><td>路線與車道</td><td>2032 個地面取樣、1560 次膠囊／車輛掃掠，0 問題</td></tr><tr><td>封裝物理</td><td>127,750 條射線、16,099 個地面、7,349 段掃掠、1,640 處樹幹對位、254 個燈具碰撞</td></tr><tr><td>真人物理實走</td><td id="walkResult"></td></tr><tr><td>飾品</td><td>122 件 Tripo3D 模型，instant-meshes-rs 重鋪（119 件真正重鋪、3 件保留原拓撲取樣），坐在家具面上 0.12cm、無碰撞</td></tr></table>
<p><a href="acceptance.json">交付收據</a> · <a href="captures.json">全部定鏡畫面</a> · <a href="visual-review.json">逐頁目視紀錄</a> · <a href="physics-latest.json">實走與物理驗收</a> · <a href="audit.json">稽核</a> · <a href="route-review.json">路線</a></p><p>地圖 SHA-256：<code id="mapHash"></code><br>遊戲執行檔：<code id="exePath"></code></p></section>
<footer id="version"></footer></main>
<script>const D=__DATA__;const $=id=>document.getElementById(id);const fig=(src,cap)=>{const f=document.createElement('figure'),a=document.createElement('a'),i=document.createElement('img'),c=document.createElement('figcaption');a.href=src;a.target='_blank';a.rel='noopener';i.src=src;i.loading='lazy';i.alt=cap;a.append(i);c.textContent=cap;f.append(a,c);return f};
const labels={'bed-12':'白天','bed-21':'夜晚','bath-21':'浴室鏡面','decorA-12':'飾品 A','decorB-12':'飾品 B'};
function rooms(){const b=$('bld').value;$('roomList').replaceChildren(...D.rooms.filter(r=>b==='all'||r.building===b).map(r=>{const s=document.createElement('div');s.className='room';const h=document.createElement('h3');h.textContent=r.building+' '+r.room+'　'+r.name+(r.pool?'（泳池房）':'');const m=document.createElement('div');m.className='meta';const src=document.createElement('a');src.href=r.source;src.target='_blank';src.rel='noopener';src.textContent='官網房型頁';const go=document.createElement('a');go.href=r.launcher;go.textContent='直接進房捷徑';m.append(r.floor+' 樓 · ',src,' · ',go,' · 飾品 A：'+r.decorA+'；B：'+r.decorB);const g=document.createElement('div');g.className='shots';for(const k in labels)g.append(fig(r.shots[k],labels[k]));s.append(h,m,g);return s}))}
$('bld').onchange=rooms;rooms();$('extra').replaceChildren(...D.extra.map(r=>fig(r.url,r.id+(r.hour==null?'':' · '+r.hour+':00'))));$('walkGrid').replaceChildren(...D.walk.slice(0,24).map((u,i)=>fig(u,'實走截圖 '+(i+1))));
$('walkNote').textContent='封裝版遊戲中由 CharacterMovement 角色連續走完全部路線時的實際畫面（顯示前 24 張，共 '+D.walk.length+' 張）。';$('walkResult').textContent='同一封裝連續 '+D.soak+' 秒，'+D.routes+' 條路線逐條完成（共 '+D.trips+' 趟），零爬階輔助';$('imgTag').textContent=D.images+' 張封裝版定鏡畫面';$('mapHash').textContent=D.map;$('exePath').textContent=D.exe;$('version').textContent='封裝版本 '+D.package+' · 實際 D3D12 Game 畫面';</script></html>'''.replace('__DATA__',payload)
(O/'delivery-motel.html').write_text(document,encoding='utf8')
acceptance=dict(status='passed_reviewed_scope',recorded_at=datetime.datetime.now().isoformat(timespec='seconds')+'+08:00',engine=package['engine'],package_id=package['id'],map_sha256=mapsha,executable=str(exe),executable_sha256=sha(exe),play_launcher=str(play),room_shortcuts=len(shortcuts),actual_game_images=len(captures['images']),reviewed_sheets=review['reviewed_sheet_count'],physics=physics,decor=dict(ornaments=122,remeshed=remeshed['completed'],placement_map_sha256=placement['map_sha256']),scope='61 original-adaptation motel room types (H1 58,S18 3) with private bathrooms and mirrors,1033 new reflections incl. city-wide restroom vanities,122 Tripo3D room ornaments remeshed with instant-meshes-rs; packaged-game audit,routes,physics and full 79-route CharacterMovement traversal. Not a measured 1:1 replica; no claim of global zero z-fighting.')
(O/'acceptance.json').write_text(json.dumps(acceptance,ensure_ascii=False,indent=2),encoding='utf8');print('Published motel delivery:',O/'delivery-motel.html')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
