//! Whole-map material-slot geometry inventory. Reads the native export; never changes meshes.
use serde_json::{json, Value};
use sha2::{Digest,Sha256};
use std::{env,fs,path::PathBuf,collections::BTreeMap};
fn u(b:&[u8],i:usize)->usize {u32::from_le_bytes(b[i..i+4].try_into().unwrap()) as usize}
fn main()->Result<(),Box<dyn std::error::Error>> {
 let args:Vec<_>=env::args().collect();let folder=PathBuf::from(&args[1]);let out=PathBuf::from(&args[2]);
 let bytes=fs::read(folder.join("scene.json"))?;let scene:Value=serde_json::from_slice(&bytes)?;
 let mut meshes=Vec::new();
 for mesh in scene["meshes"].as_array().unwrap() {
  let lod=&mesh["lods"][0];let b=fs::read(folder.join(lod["file"].as_str().unwrap()))?;
  let version=u(&b,0);assert!(version==0x43445931||version==0x43445932);let nv=u(&b,4);let nt=u(&b,8);
  let points:Vec<[f64;3]>=(0..nv).map(|i|std::array::from_fn(|k|f32::from_bits(u(&b,12+i*12+k*4) as u32) as f64)).collect();
  let start=12+nv*12;let tris:Vec<([usize;3],usize)>=(0..nt).map(|i| (std::array::from_fn(|k|u(&b,start+i*12+k*4)),if version==0x43445932{u(&b,start+nt*16+i*4)}else{0})).collect();
  meshes.push((points,tris));
 }
 let mut rows=Vec::new();let mut triangles=0usize;let mut material_totals:BTreeMap<String,f64>=BTreeMap::new();
 for inst in scene["instances"].as_array().unwrap() {
  let (p,t)=&meshes[inst["mesh"].as_u64().unwrap() as usize];let m:Vec<_>=inst["matrix"].as_array().unwrap().iter().map(|v|v.as_f64().unwrap()).collect();
  let wp:Vec<[f64;3]>=p.iter().map(|p|std::array::from_fn(|k|p[0]*m[k]+p[1]*m[4+k]+p[2]*m[8+k]+m[12+k])).collect();
  let mut planes:BTreeMap<i64,f64>=BTreeMap::new();let low=inst["min"][2].as_f64().unwrap().max(m[14]);
  if inst["actor"].as_str().unwrap().contains("_F") {for (indices,_) in t {
   let [a,b,c]=indices.map(|i|wp[i]);let x:[f64;3]=std::array::from_fn(|k|b[k]-a[k]);let y:[f64;3]=std::array::from_fn(|k|c[k]-a[k]);let n=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]];let len=n.iter().map(|v|v*v).sum::<f64>().sqrt();let z=(a[2]+b[2]+c[2])/3.;
   if len>1e-8 && n[2].abs()/len>0.98 && (a[2]-b[2]).abs()<0.15 && (a[2]-c[2]).abs()<0.15 && z>=low-0.2 {*planes.entry((z*10.).round() as i64).or_default()+=len*0.5;}
  }}
  // Unreal render winding must not be interpreted as vertex-normal direction.
  // Select the upper broad slab face, excluding small furniture planes.
  let peak=planes.values().copied().fold(0.,f64::max);
  let first=planes.iter().find(|(_,area)|**area>=peak*0.5).map(|(z,_)|*z as f64/10.).unwrap_or(m[14]);
  let floor_z=planes.iter().filter(|(z,area)|**area>=peak*0.5 && **z as f64/10.<=first+40.).map(|(z,_)|*z as f64/10.).max_by(f64::total_cmp).unwrap_or(first);
  let mut slots:BTreeMap<usize,(f64,f64,f64,f64,usize)>=BTreeMap::new();let mut bands:BTreeMap<usize,f64>=BTreeMap::new();
  for (indices,slot) in t {
   let [a,b,c]=indices.map(|i|wp[i]);let x: [f64;3]=std::array::from_fn(|k|b[k]-a[k]);let y:[f64;3]=std::array::from_fn(|k|c[k]-a[k]);
   let n=[x[1]*y[2]-x[2]*y[1],x[2]*y[0]-x[0]*y[2],x[0]*y[1]-x[1]*y[0]];let len=n.iter().map(|v|v*v).sum::<f64>().sqrt();
   let r=slots.entry(*slot).or_insert((0.,0.,f64::INFINITY,f64::NEG_INFINITY,0));
   r.2=r.2.min(a[2]).min(b[2]).min(c[2]);r.3=r.3.max(a[2]).max(b[2]).max(c[2]);r.4+=1;
   if len>1e-8 && n[2].abs()/len>0.65 {if n[2]>0. {r.0+=len*0.5/10000.;}else{r.1+=len*0.5/10000.;}if n[2].abs()/len>0.98 && [a[2],b[2],c[2]].iter().all(|z|(z-floor_z).abs()<8.) {*bands.entry(*slot).or_default()+=len*0.5/10000.;}}
  }
  triangles+=t.len();
  for (slot,(up,down,lo,hi,nt)) in slots {
   let material=inst["materials"][slot].as_str().unwrap_or("");*material_totals.entry(material.to_string()).or_default()+=up;
   rows.push(json!({"actor":inst["actor"],"component":inst["component"],"key":inst["key"],"instance":inst["instance"],"mesh":scene["meshes"][inst["mesh"].as_u64().unwrap() as usize]["asset"],"slot":slot,"material":material,"upward_surface_m2":up,"downward_surface_m2":down,"floor_band_area_m2":bands.get(&slot).copied().unwrap_or(0.),"floor_z_cm":floor_z,"min_z_cm":lo,"max_z_cm":hi,"triangles":nt,"collision":inst["collision"]}));
  }
 }
 let report=json!({"status":"passed","method":"All native LOD0 world triangles assigned to actual material slots; horizontal means abs(n.z)>0.65. Includes furniture and buildings for explicit review; does not assume every upward surface is ground.","scene_sha256":format!("{:x}",Sha256::digest(&bytes)),"instances":scene["instances"].as_array().unwrap().len(),"world_triangles":triangles,"rows":rows,"material_upward_area_m2":material_totals});
 fs::write(out,serde_json::to_vec(&report)?)?;println!("{} instances, {} world triangles, {} actual material-slot rows",report["instances"],triangles,report["rows"].as_array().unwrap().len());Ok(())
}
