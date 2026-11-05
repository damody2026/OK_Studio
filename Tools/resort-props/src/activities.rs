//! Activity furniture from immutable, remeshed metric building blocks.
use super::*;
use std::f64::consts::TAU;
fn rotated_box(m:&mut Model,p:[f64;3],s:[f64;3],a:f64,mat:usize){m.b(p,s,mat);m.parts.last_mut().unwrap().rot=a;}
fn recipe(id:&str,lod:usize)->Model{
 let mut m=Model::new();
 match id{
 "library-wall"=>{
  m.b([0.,0.22,0.],[2.4,0.08,2.65],0);
  for x in [-1.17,0.,1.17]{m.b([x,0.,0.],[0.06,0.52,2.65],0);}
  for k in 0..7{let z=0.12+k as f64*0.39;m.b([0.,0.,z],[2.4,0.54,0.045],0);
   if k<6{for j in 0..25{let h=0.23+((j*17+k*11)%10) as f64*0.009;let w=0.055+((j+k)%3) as f64*0.008;m.b([-1.08+j as f64*0.087,-0.03,z+0.05],[w,0.28,h],2+(j*3+k)%5);}}
  }
  m.b([0.,-0.255,2.57],[2.28,0.015,0.025],6);
 },
 "practice-stage"=>{
  m.b([0.,0.,0.],[6.,8.,0.45],0);
  for k in 0..3{m.b([-3.15-0.3*k as f64,0.,0.],[0.3,3.2,0.45-0.15*k as f64],7);}
  for y in [-3.8,3.8]{m.b([2.65,y,0.45],[0.18,0.18,3.6],1);m.b([-2.65,y,0.45],[0.18,0.18,3.6],1);m.beam([-2.65,y,4.05],[2.65,y,4.05],0.12,1);}
  m.beam([2.65,-3.8,4.05],[2.65,3.8,4.05],0.12,1);
  m.b([2.9,0.,0.45],[0.12,7.8,3.6],0);
  for y in [-3.1,3.1]{for k in 0..7{m.c([2.7,y-0.6+k as f64*0.17,0.45],[0.22,0.22,3.5],5);}}
 },
 "stage-speaker"=>{m.b([0.,0.,0.],[0.55,0.45,1.1],1);for z in [0.3,0.78]{m.beam([0.,-0.24,z],[0.,-0.255,z],0.34,7);}m.b([0.,0.,1.1],[0.5,0.4,0.035],1);},
 "music-stand"=>{m.c([0.,0.,0.],[0.45,0.45,0.035],1);m.c([0.,0.,0.035],[0.035,0.035,1.05],1);m.b([0.,0.,1.08],[0.52,0.045,0.38],1);m.b([0.,-0.03,1.1],[0.43,0.01,0.31],2);},
 "fountain"=>{
  m.c([0.,0.,0.],[6.2,6.2,0.15],7);
  let n=if lod==0{40}else if lod==1{28}else{20};
  for i in 0..n {let a=TAU*i as f64/n as f64;rotated_box(&mut m,[2.8*a.cos(),2.8*a.sin(),0.15],[0.38,TAU*2.8/n as f64*1.02,0.48],a,7);}
  m.c([0.,0.,0.48],[5.18,5.18,0.03],3);
  m.c([0.,0.,0.2],[0.5,0.5,1.35],7);m.c([0.,0.,1.5],[1.65,1.65,0.12],7);m.c([0.,0.,1.62],[1.5,1.5,0.025],3);
  m.c([0.,0.,1.63],[0.22,0.22,0.65],7);m.c([0.,0.,2.25],[0.85,0.85,0.1],7);m.c([0.,0.,2.35],[0.75,0.75,0.025],3);
  let k=if lod==2{4}else{8};for j in 0..k{let a=TAU*j as f64/k as f64;let mut prev=[0.,0.,2.45];for t in 1..=8{let q=t as f64/8.;let next=[2.1*q*a.cos(),2.1*q*a.sin(),2.45+1.4*q-3.5*q*q];m.beam(prev,next,0.035,6);prev=next;}}
 },
 "easel"=>{m.beam([-0.42,-0.3,0.],[0.,0.,1.7],0.045,0);m.beam([0.42,-0.3,0.],[0.,0.,1.7],0.045,0);m.beam([0.,0.55,0.],[0.,0.,1.5],0.045,0);m.b([0.,0.,0.72],[0.85,0.08,0.06],0);m.b([0.,0.02,0.78],[0.72,0.035,0.65],2);m.b([0.,-0.008,0.82],[0.66,0.01,0.56],7);},
 "picture-rack"=>{m.b([0.,0.,0.],[1.6,0.45,0.08],0);for k in 0..3{let h=0.17+k as f64*0.3;m.b([0.,k as f64*0.06,h-0.04],[1.6,0.34,0.04],0);m.b([0.,0.09+k as f64*0.06,h],[1.6,0.08,0.33],0);m.b([0.,-0.11+k as f64*0.06,h],[1.6,0.035,0.08],0);}for x in [-0.77,0.77]{m.b([x,0.,0.],[0.06,0.4,1.2],0);m.b([x,0.2,1.2],[0.035,0.035,0.5],0);}},
 "art-display"=>{m.b([0.,0.,0.],[1.5,0.45,0.1],0);m.b([0.,0.19,0.],[1.5,0.05,1.65],0);for z in [0.12,0.63,1.14]{m.b([0.,0.,z],[1.5,0.45,0.06],0);for x in [-0.7,0.7]{m.b([x,0.,0.],[0.06,0.45,1.65],0);}}},
 "service-counter"=>{m.b([-0.45,0.,0.],[1.4,0.68,0.97],0);m.b([-0.45,0.,0.97],[1.5,0.8,0.08],7);m.b([0.85,0.,0.],[1.1,0.68,0.06],0);m.b([0.85,0.,0.74],[1.1,0.8,0.06],7);for x in [0.34,1.36]{m.b([x,0.29,0.],[0.07,0.07,0.74],0);}m.b([-0.45,-0.35,0.25],[1.3,0.03,0.44],3);},
 "feed-dispenser"=>{m.b([0.,0.,0.],[0.55,0.5,0.12],7);m.b([0.,0.,0.12],[0.3,0.3,0.82],1);m.c([0.,0.,0.94],[0.55,0.55,0.55],6);m.c([0.,0.,1.49],[0.59,0.59,0.06],1);m.b([0.,-0.29,1.05],[0.23,0.1,0.12],1);m.b([0.,-0.3,0.88],[0.3,0.22,0.05],1);},
 "festival-gate"=>{for x in [-3.2,3.2]{m.b([x,0.,0.],[0.26,0.26,3.3],0);m.b([x,0.,0.],[0.8,0.8,0.15],7);}m.b([0.,0.,3.2],[7.1,0.3,0.24],0);m.b([0.,0.,2.58],[5.2,0.13,0.55],3);},
 "queue-post"=>{m.c([0.,0.,0.],[0.3,0.3,0.045],1);m.c([0.,0.,0.045],[0.05,0.05,0.85],1);m.c([0.,0.,0.9],[0.1,0.1,0.08],6);},
 "calculator"=>{m.b([0.,0.,0.],[0.09,0.16,0.014],1);m.b([0.,0.045,0.014],[0.075,0.038,0.002],4);for x in -1..=1{for y in 0..4{m.b([x as f64*0.024,-0.06+y as f64*0.023,0.014],[0.018,0.017,0.004],if y==3{6}else{7});}}},
 "dango"=>{for k in 0..3{m.c([0.,-0.055+k as f64*0.055,0.02],[0.052,0.052,0.045],if k==0{5}else if k==1{2}else{4});}m.beam([0.,-0.15,0.04],[0.,0.13,0.04],0.004,0);m.b([0.,0.,0.],[0.09,0.32,0.012],7);},
 "candy"=>{m.c([0.,0.,0.],[0.2,0.2,0.025],7);for k in 0..12{let a=k as f64*2.4;let r=0.02+(k%3) as f64*0.022;m.c([r*a.cos(),r*a.sin(),0.025],[0.026,0.026,0.022],3+k%4);}},
 "flyer-stand"=>{m.b([0.,0.,0.],[0.45,0.4,0.05],1);m.b([0.,0.1,0.05],[0.05,0.05,1.1],1);m.b([0.,0.,0.95],[0.45,0.035,0.48],0);for x in [-0.12,0.12]{m.b([x,-0.04,0.99],[0.2,0.03,0.3],2);}},
 "sketchbook"=>{m.b([0.,0.,0.],[0.3,0.42,0.025],0);m.b([0.,0.,0.025],[0.29,0.41,0.008],2);for k in 0..8{m.c([-0.148,-0.18+k as f64*0.045,0.02],[0.012,0.012,0.025],1);}},
 "practice-marker"=>{m.c([0.,0.,0.],[0.42,0.42,0.06],7);m.c([0.,0.,0.06],[0.28,0.28,0.3],3);m.c([0.,0.,0.36],[0.15,0.15,0.18],6);},
 "staff-locker"=>{m.b([0.,0.,0.],[1.2,0.45,1.8],1);for x in [-0.39,0.,0.39]{m.b([x,-0.232,0.08],[0.37,0.025,1.64],3);m.b([x+0.12,-0.255,0.9],[0.025,0.035,0.12],1);}},
 "night-stall-stock"=>{m.b([0.,0.,0.],[1.7,0.65,0.9],0);m.b([0.,0.,0.9],[1.8,0.75,0.07],7);for x in [-0.57,0.,0.57]{m.b([x,0.,0.97],[0.48,0.5,0.035],1);for k in 0..4{m.c([x-0.12+(k%2) as f64*0.23,-0.11+(k/2) as f64*0.23,1.005],[0.15,0.15,0.045],5+k%2);}}},
 "binoculars"=>{m.c([0.,0.,0.],[0.6,0.6,0.08],7);m.c([0.,0.,0.08],[0.12,0.12,1.05],1);for x in [-0.09,0.09]{m.beam([x,-0.18,1.22],[x,0.22,1.3],0.1,1);}},
 "fish-pond"=>{m.b([0.,0.,0.],[8.,5.,0.12],7);m.b([0.,0.,0.39],[7.5,4.5,0.025],3);for x in [-3.88,3.88]{m.b([x,0.,0.12],[0.24,5.,0.42],7);}for y in [-2.38,2.38]{m.b([0.,y,0.12],[7.6,0.24,0.42],7);}},
 "platform"=>{m.b([0.,0.,0.],[1.,1.,0.12],7);},
 "sign"=>{m.b([0.,0.,0.],[1.,0.035,1.],7);},
 "umbrella"=>{m.c([0.,0.,0.],[0.018,0.018,0.85],1);m.parts.push(Part{shape:2,p:[0.,0.,0.7],s:[1.1,1.1,0.22],rot:0.,tilt:0.,mat:3});for k in 0..8{let a=k as f64*TAU/8.;m.beam([0.,0.,0.92],[0.54*a.cos(),0.54*a.sin(),0.7],0.008,1);}m.c([0.,0.,0.],[0.035,0.035,0.15],0);},
 _=>unreachable!()
 }
 if lod==2&&m.parts.len()>20{let mut n=0;m.parts.retain(|p|{n+=1;p.s.iter().copied().fold(0.,f64::max)>0.045||n%2==0});}
 m
}
pub fn build(root:&Path)->R<()>{
 let base=root.join("output/street-social-city-production");let out=base.join("activity-scenes-v1");fs::create_dir_all(out.join("models"))?;fs::create_dir_all(out.join("textures"))?;
 for name in ["teak","linen","stone"]{fs::copy(base.join(format!("resort-streetscape-v1/textures/{name}.png")),out.join(format!("textures/{name}.png")))?;}
 let mut shapes=vec![];let mut proof=vec![];
 for id in ["unit-panel","unit-cylinder"]{let path=base.join(format!("campus-v1/components/{id}/remesh/remeshed-candidate.glb"));let r=read_json(&path.with_file_name("remesh-report.json"))?;assert_eq!(r["status"],"passed");assert_eq!(r["output_sha256"],sha(&path)?);shapes.push(source(&path)?);proof.push(json!({"component":id,"path":path,"sha256":sha(&path)?,"remesh_report":r}));}
 let (canopy,canopy_proof)=canopy::prepare(&out)?;shapes.push(canopy);proof.push(canopy_proof);
 let ids=["fountain","easel","picture-rack","art-display","service-counter","feed-dispenser","festival-gate","queue-post","calculator","dango","candy","flyer-stand","sketchbook","practice-marker","staff-locker","night-stall-stock","binoculars","fish-pond","platform","sign","umbrella","library-wall","practice-stage","stage-speaker","music-stand"];
 let mut rows=vec![];
 for id in ids{let mut lods=vec![];for lod in 0..3{let path=out.join(format!("models/{id}-LOD{lod}.glb"));let (tri,bounds)=glb(&path,&recipe(id,lod),&shapes,id)?;assert!(tri<10000);lods.push(json!({"path":path,"sha256":sha(&path)?,"triangles":tri,"bounds_m":bounds}));}rows.push(json!({"id":id,"provider":"assembled previously remeshed components","lods":lods}));}
 write(&out.join("models.json"),&json!({"status":"passed","models":rows,"remesh_provenance":proof,"policy":"Reuse previously remeshed metric components; do not remesh a whole assembly and destroy joins. Organic models have a separate mandatory fresh remesh receipt."}))?;
 let mut ground=vec![];for (x,y) in [(1020.,750.),(620.,184.),(572.5,800.)]{let mut heights=vec![];for dx in [-10.,0.,10.]{for dy in [-8.,0.,8.]{heights.push(placement::terrain_height(root,x+dx,y+dy)?);}}ground.push(json!({"x":x,"y":y,"heights":heights,"max":heights.iter().copied().fold(f64::MIN,f64::max)}));}write(&out.join("terrain-samples.json"),&json!(ground))?;
 println!("Built {} activity furniture models with 3 LODs",ids.len());Ok(())
}
