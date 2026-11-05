-- Preserve the original depth-repair checks across the documented flat-campus mesh rebake.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local base='C:/portable/OpenKoikatsu/output/street-social-city-production/'
local function read(p)local f=assert(io.open(p,'rb'));local d=j.decode(f:read('*a'));f:close();return d end
local out=base..'immersion-v1/';local survey=read(out..'surface-ledger-review.json');local flat=read(base..'flat-campus-v1/install.json');local map=h.sha256_file('StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')
local equivalence
if survey.map_sha256~=map then
 local snapshot=read(out..'preservation-after.json');local audit=read(out..'audit.json');assert(snapshot.map_sha256==map and audit.map_sha256==map and audit.status=='passed');local lookup={};for _,r in ipairs(snapshot.components)do lookup[r.actor..'::'..r.component]=r end
 local function same(a,b)if type(a)~=type(b)then return false end;if type(a)=='number'then return math.abs(a-b)<.00001 end;if type(a)~='table'then return a==b end;for k,v in pairs(a)do if not same(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
 local original_count,replacement_count=0,0
 for _,kind in ipairs({'street','tactile'})do
  for _,r in ipairs(survey.ledgers[kind].originals)do
   local q=assert(lookup[r.actor..'::'..r.component]);assert(not r.missing and r.mesh==q.mesh and r.instance_count==#(q.instances or {}) and r.visible==q.visible and r.hidden==q.hidden and r.collision==q.collision and same(r.materials,q.materials) and same(r.transform,q.transform),'Current original surface component differs '..r.actor);original_count=original_count+1
  end
  for _,r in ipairs(survey.ledgers[kind].replacements)do
   local current={};for _,q in ipairs(snapshot.components)do if q.actor==r.actor then current[#current+1]=q end end;assert(#r.components==1 and #current==1);local old,q=r.components[1],current[1];assert(old.mesh==q.mesh and old.visible==q.visible and old.hidden==q.hidden and old.collision==q.collision and same(old.transform,q.transform),'Current replacement differs '..r.actor);replacement_count=replacement_count+1
  end
 end
 equivalence={status='current_native_snapshot_fields_match_earlier_surface_survey',map_sha256=map,earlier_survey_map_sha256=survey.map_sha256,earlier_survey_sha256=h.sha256_file(out..'surface-ledger-review.json'),current_native_audit_sha256=h.sha256_file(out..'audit.json'),current_snapshot_sha256=h.sha256_file(out..'preservation-after.json'),original_components_checked=original_count,replacement_components_checked=replacement_count,fields_requiring_cooked_replay={'cast_hidden_shadow','replacement_ownership_tags'},scope='Do not relabel the earlier survey as a new native test. Current saved/reopened snapshot proves selected mesh,transform,instance count,visibility,materials and collision are unchanged. Final actual cooked ValidateSurfaceRendering independently rechecks all original fields including hidden shadows and ownership.'};local f=assert(io.open(out..'surface-ledger-current-equivalence.json','wb'));f:write(j.encode(equivalence));f:close()
end
local mapping={};for _,r in ipairs(flat.meshes)do mapping[r.key]=r end
for _,kind in ipairs({'street','tactile'})do
 local source=base..'day-night-v1/'..kind..'-surface-install.json';local d=read(source);local s=survey.ledgers[kind];assert(#d.changes==#s.originals and #d.replacements==#s.replacements)
 for i,r in ipairs(s.originals)do assert(not r.missing and r.mesh==r.expected_mesh and r.instance_count==r.expected_instances and not r.visible and r.hidden and not r.hidden_shadow and r.collision==r.expected_collision and j.encode(r.materials)==j.encode(r.expected_materials),'Original depth preservation mismatch '..kind..' '..i)end
 local migrations={}
 for i,r in ipairs(d.replacements)do
  local now=s.replacements[i];assert(now.actor==r.actor and #now.components==1);local c=now.components[1];local f=assert(mapping[r.actor..'::'..r.component.component],'Missing flat-campus provenance '..r.actor)
  assert(f.before==r.mesh and f.after==c.mesh,'Unexplained replacement '..r.actor)
  assert(c.visible and not c.hidden and c.collision=='NoCollision');assert(j.encode(c.transform.translation)==j.encode({0.,0.,0.}) and j.encode(c.transform.scale)==j.encode({1.,1.,1.}))
  local tag=kind=='street' and 'CityDepthStreetV1' or 'CityDepthTactileV1';local tagged=false;for _,t in ipairs(now.tags)do if t==tag then tagged=true end end;assert(tagged)
  migrations[#migrations+1]={actor=r.actor,before=r.mesh,after=c.mesh,provenance_key=f.key};r.mesh=c.mesh;r.component.mesh=c.mesh
 end
 d.ledger_migration={status='passed',map_sha256=map,source_path=source,source_sha256=h.sha256_file(source),flat_install_sha256=h.sha256_file(base..'flat-campus-v1/install.json'),native_survey_sha256=h.sha256_file(out..'surface-ledger-review.json'),reason='Documented flat-campus world-space vertex rebake replaced render mesh identities. Original instance counts, materials, collision and hidden rendering checks retained verbatim. Native runtime checks remain mandatory.',changes=migrations}
 if equivalence then d.ledger_migration.current_snapshot_equivalence=equivalence end
 local path=out..kind..'-surface-current-ledger.json';local f=assert(io.open(path,'wb'));f:write(j.encode(d));f:close();print(kind..': migrated '..#migrations..' documented replacements; preserved '..#d.changes..' original checks')
end
