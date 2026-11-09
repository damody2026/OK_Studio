import * as THREE from 'three';
import { GLTFLoader } from './vendor/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from './vendor/examples/jsm/controls/OrbitControls.js';
const $ = id => document.getElementById(id);
const manifest = await fetch('./variation-manifest.json').then(r=>r.json());
const acceptance = await fetch('./acceptance.json').then(r=>r.json());
const loader = new GLTFLoader(), textures = new THREE.TextureLoader(), cache = new Map(), masks = new Map();
const renderer = new THREE.WebGLRenderer({antialias:true,preserveDrawingBuffer:true});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.5)); renderer.shadowMap.enabled=true; renderer.shadowMap.type=THREE.PCFSoftShadowMap;
renderer.outputColorSpace=THREE.SRGBColorSpace; renderer.toneMapping=THREE.ACESFilmicToneMapping; renderer.toneMappingExposure=1.1;
$('view').append(renderer.domElement);
const scene=new THREE.Scene();scene.background=new THREE.Color('#dce8e1');
const camera=new THREE.PerspectiveCamera(38,1,.05,800), controls=new OrbitControls(camera,renderer.domElement);
controls.enableDamping=true;controls.maxPolarAngle=Math.PI*.49;
scene.add(new THREE.HemisphereLight(0xe9f6ff,0x73856b,2.0));
const sun=new THREE.DirectionalLight(0xfff2df,3.2);sun.position.set(25,40,20);sun.castShadow=true;sun.shadow.mapSize.set(2048,2048);sun.shadow.camera.left=-40;sun.shadow.camera.right=40;sun.shadow.camera.top=40;sun.shadow.camera.bottom=-40;sun.shadow.camera.far=120;sun.shadow.bias=-.0003;scene.add(sun);
const fill=new THREE.DirectionalLight(0xbfdcff,1.1);fill.position.set(-15,15,-12);scene.add(fill);
const ground=new THREE.Mesh(new THREE.PlaneGeometry(300,300),new THREE.MeshStandardMaterial({color:0xcbd7c8,roughness:.95}));ground.rotation.x=-Math.PI/2;ground.position.y=-.012;ground.receiveShadow=true;scene.add(ground);
let content=new THREE.Group();scene.add(content);let items=[],selected=0,current=null,ticket=0,modelReady=false;
const settings = new Map();
function optionsFor(asset){return manifest.models.filter(q=>q.id===asset).sort((a,b)=>a.level-b.level);}
function initialSettings(asset){
 const spec=optionsFor(asset)[0], tree=['camphor','cherry'].includes(asset);
 const actual=manifest.instances.filter(q=>q.asset===asset).slice(0,6);
 return Array.from({length:6},(_,i)=>({hex:spec.palettes[i%spec.palettes.length].hex,yaw:tree?(actual[i]?.after.variation.yaw_delta_deg??0):0,xy:tree?(actual[i]?.after.variation.horizontal_factor??1):1,height:tree?(actual[i]?.after.variation.height_factor??1):1}));
}
function getSettings(){if(!settings.has(current.id))settings.set(current.id,initialSettings(current.id));return settings.get(current.id);}
function paintMaterial(material,mask,reference,color){
 const m=material.clone();const uniform={value:new THREE.Color(color)};
 m.onBeforeCompile=shader=>{
  shader.uniforms.streetPaint={value:mask};shader.uniforms.streetTarget=uniform;shader.uniforms.streetReference={value:reference};
  shader.fragmentShader='uniform sampler2D streetPaint;uniform vec3 streetTarget;uniform float streetReference;\n'+shader.fragmentShader;
  shader.fragmentShader=shader.fragmentShader.replace('#include <map_fragment>',`#include <map_fragment>
   float streetMask = texture2D(streetPaint, vMapUv).r;
   float streetShade = clamp(max(max(diffuseColor.r,diffuseColor.g),diffuseColor.b)/max(streetReference,0.025),0.15,1.8);
   diffuseColor.rgb = mix(diffuseColor.rgb,streetTarget*streetShade,streetMask);`);
 };
 m.customProgramCacheKey=()=> 'street-masked-paint-v1';m.userData.streetTarget=uniform;return m;
}
async function load(asset,level){
 const ownTicket=++ticket;modelReady=false;$('error').textContent='';$('status').textContent='載入模型與共用材質…';$('snapshot').style.display='none';$('download').style.display='none';
 try{
  current=optionsFor(asset).find(q=>q.level===level)||optionsFor(asset)[0];
  $('lod').value=String(current.level);for(const opt of $('lod').options)opt.disabled=!optionsFor(asset).some(q=>q.level===Number(opt.value));
  const key=current.path;if(!cache.has(key))cache.set(key,loader.loadAsync(key));const gltf=await cache.get(key);if(ownTicket!==ticket)return;
  const vehicle=['scooter','bicycle'].includes(asset);let mask=null;
  if(vehicle){if(!masks.has(asset)){const value=await textures.loadAsync(current.mask);value.flipY=false;value.colorSpace=THREE.NoColorSpace;masks.set(asset,value);}mask=masks.get(asset);}
  if(ownTicket!==ticket)return;
  content.traverse(o=>{if(o.isMesh){for(const m of Array.isArray(o.material)?o.material:[o.material])m.dispose();}});scene.remove(content);content=new THREE.Group();scene.add(content);items=[];
  const sourceBounds=new THREE.Box3().setFromObject(gltf.scene),size=sourceBounds.getSize(new THREE.Vector3()),center=sourceBounds.getCenter(new THREE.Vector3());
  const spacingX=Math.max(size.x*1.4,vehicle?2.3:8.6),spacingZ=Math.max(size.z*1.5,vehicle?2.6:8.5);
  for(let i=0;i<6;i++){
   const wrapper=new THREE.Group(),object=gltf.scene.clone(true),mats=[];
   object.position.x-=center.x;object.position.z-=center.z;object.position.y-=sourceBounds.min.y;
   object.traverse(o=>{if(!o.isMesh)return;o.castShadow=true;o.receiveShadow=true;const originals=Array.isArray(o.material)?o.material:[o.material];const mm=originals.map(m=>{
    const result=vehicle?paintMaterial(m,mask,current.paint_reference_linear_value,'#ffffff'):m.clone();
    if(vehicle||result.alphaTest>0)mats.push(result);return result;
   });o.material=Array.isArray(o.material)?mm:mm[0];});
   wrapper.position.set(((i%3)-1)*spacingX,0,(Math.floor(i/3)-.5)*spacingZ);wrapper.add(object);content.add(wrapper);items.push({wrapper,mats});
  }
  selected=Math.min(selected,5);apply();syncControls();rebuildSwatches();rebuildLabels();
  const bounds=new THREE.Box3().setFromObject(content);const extent=bounds.getSize(new THREE.Vector3()),mid=bounds.getCenter(new THREE.Vector3());const span=Math.max(extent.x,extent.y*1.4,extent.z*1.2);controls.target.copy(mid);camera.position.copy(mid).add(new THREE.Vector3(span*.7,span*.5,span*1.05));camera.near=.05;camera.far=800;camera.updateProjectionMatrix();controls.update();
  modelReady=true;$('status').textContent=`${asset} · LOD ${current.level} · 每件 ${current.triangles.toLocaleString()} 三角面 · 6 件展示 · 幾何增加 0 面 · 種子 ${manifest.seed}`;
 }catch(error){if(ownTicket!==ticket)return;$('error').textContent=error.stack||String(error);$('status').textContent='載入失敗，請查看錯誤訊息。';console.error(error);}
}
function apply(){if(!current)return;const values=getSettings(),enabled=$('variation').checked,vehicle=['scooter','bicycle'].includes(current.id);
 items.forEach((item,i)=>{
  const value=enabled?values[i]:{hex:current.palettes[0].hex,yaw:0,xy:1,height:1};
  item.wrapper.rotation.y=THREE.MathUtils.degToRad(value.yaw+(vehicle?25:0));item.wrapper.scale.set(value.xy,value.height,value.xy);
  item.mats.forEach(m=>{if(vehicle)m.userData.streetTarget.value.set(value.hex);else m.color.set(value.hex);});
 });
}
function syncControls(){if(!current)return;const q=getSettings()[selected];$('color').value=q.hex;$('hex').value=q.hex;$('yaw').value=q.yaw;$('xy').value=q.xy*100;$('height').value=q.height*100;const tree=['camphor','cherry'].includes(current.id);for(const id of ['yaw','xy','height'])$(id).disabled=!tree;$('yawValue').textContent=q.yaw.toFixed(1)+'°';$('xyValue').textContent=(q.xy*100).toFixed(1)+'%';$('heightValue').textContent=(q.height*100).toFixed(1)+'%';}
function rebuildLabels(){const values=getSettings();$('labels').replaceChildren(...values.map((q,i)=>{const b=document.createElement('button');b.textContent=`${i+1} · ${q.hex.toUpperCase()}`;b.className=i===selected?'active':'';b.onclick=()=>{selected=i;syncControls();rebuildLabels();};return b;}));}
function rebuildSwatches(){$('swatches').replaceChildren(...current.palettes.map(q=>{const b=document.createElement('button');b.className='swatch';b.style.background=q.hex;b.title=q.name;b.setAttribute('aria-label',q.name);b.onclick=()=>{getSettings()[selected].hex=q.hex;apply();syncControls();rebuildLabels();};return b;}));}
$('asset').onchange=()=>{selected=0;load($('asset').value,Number($('lod').value));};$('lod').onchange=()=>load($('asset').value,Number($('lod').value));
$('color').oninput=()=>{if(!current)return;getSettings()[selected].hex=$('color').value;$('hex').value=$('color').value;apply();rebuildLabels();};
$('hex').oninput=()=>{const value=$('hex').value;if(!/^#[0-9a-f]{6}$/i.test(value)||!current)return;getSettings()[selected].hex=value;$('color').value=value;apply();rebuildLabels();};
for(const id of ['yaw','xy','height'])$(id).oninput=()=>{const q=getSettings()[selected];q[id]=Number($(id).value)/(id==='yaw'?1:100);apply();syncControls();};
$('variation').onchange=apply;$('reset').onclick=()=>{settings.set(current.id,initialSettings(current.id));$('variation').checked=true;apply();syncControls();rebuildLabels();};
$('snapshotButton').onclick=async()=>{if(!modelReady)return;controls.update();renderer.render(scene,camera);const data=renderer.domElement.toDataURL('image/png');$('download').href=data;$('download').download=`${current.id}-LOD${current.level}.png`;$('download').style.display='inline-block';$('snapshot').src=data;$('snapshot').style.display='block';
 try{const blob=await new Promise(resolve=>renderer.domElement.toBlob(resolve,'image/png'));const r=await fetch(`/capture/${current.id}-LOD${current.level}.png`,{method:'POST',headers:{'Content-Type':'image/png','X-Street-Preview':'1'},body:blob});if(!r.ok)throw new Error('PNG保存失敗');$('status').textContent+=' · 預覽已存到成果頁';}catch(error){$('error').textContent=String(error);}
};
$('settings').onclick=()=>{const blob=new Blob([JSON.stringify({schema:1,source_manifest_sha256:acceptance.manifest_sha256,asset:current.id,lod:current.level,enabled:$('variation').checked,preview_settings:getSettings(),runtime_contract:manifest.runtime,native_unreal_updated:false},null,2)],{type:'application/json'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='street-variation-settings.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
function resize(){const element=$('view');renderer.setSize(element.clientWidth,element.clientHeight,false);camera.aspect=element.clientWidth/element.clientHeight;camera.updateProjectionMatrix();}new ResizeObserver(resize).observe($('view'));resize();
renderer.setAnimationLoop(()=>{controls.update();renderer.render(scene,camera);});
await load(new URL(location.href).searchParams.get('asset')||'scooter',Number(new URL(location.href).searchParams.get('lod')||0));
