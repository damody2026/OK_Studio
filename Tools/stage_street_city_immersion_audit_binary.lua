-- Binary-only checkpoint on the same cooked map: retain all previous stages.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1';local env=root..'/output/street-social-city-production/day-night-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=j.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(j.encode(d));f:close()end
local p=read(env..'/package.json');local b=read(out..'/native-audit-build/build.json');local map=h.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')
assert(p.engine=='E:/PhysX/UE5.8' and p.exit_code==0 and p.map_sha256==map and b.status=='passed' and b.map_sha256==map and b.host==p.host)
assert(h.sha256_file(b.game_executable)==b.game_sha256 and p.target==out..'/packages/'..p.id)
local id=os.date('%Y%m%d-%H%M%S');local target=out..'/packages/'..id;local source=p.target..'/Stage';local exe_rel='Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'
local script=[=[
$source=[IO.Path]::GetFullPath('__SOURCE__');$destination=[IO.Path]::GetFullPath('__TARGET__/Stage');if(Test-Path -LiteralPath $destination){throw 'Destination exists'}
$items=@(Get-ChildItem -LiteralPath $source -Recurse -Force);if($items|Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }){throw 'Stage contains reparse points; refuse traversal'}
New-Item -ItemType Directory -Path $destination -ErrorAction Stop|Out-Null
foreach($item in $items){$relative=$item.FullName.Substring($source.Length).TrimStart('\');$new=[IO.Path]::GetFullPath((Join-Path $destination $relative));if(!$new.StartsWith($destination+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Target outside fresh stage'};if($item.PSIsContainer){New-Item -ItemType Directory -Path $new -Force|Out-Null}else{if($relative.Replace('\','/') -eq '__EXEREL__'){Copy-Item -LiteralPath '__EXESOURCE__' -Destination $new -ErrorAction Stop}else{New-Item -ItemType HardLink -Path $new -Target $item.FullName -ErrorAction Stop|Out-Null}}}
]=]
script=script:gsub('__SOURCE__',source):gsub('__TARGET__',target):gsub('__EXEREL__',exe_rel):gsub('__EXESOURCE__',b.game_executable)
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',script},{hide=true,timeout=180}).code==0)
assert(h.sha256_file(target..'/Stage/'..exe_rel)==b.game_sha256)
local n={};for k,v in pairs(p)do n[k]=v end;n.id=id;n.target=target;n.prebuilt_game_sha256=b.game_sha256;n.prebuilt_from_package=p.id;n.binary_overlay_parent_package=p.id;n.scope='Same cooked map/assets as parent; isolated E-engine opt-in audit binary refreshed. Immutable parent retained; unchanged staged data hardlinked and must never be edited in place.';n.status='built_requires_runtime_validation'
write(out..'/package-before-binary-overlay-'..id..'.json',p);write(target..'/binary-overlay.json',{status='passed',parent=p,package=n,build_receipt=out..'/native-audit-build/build.json',data_policy='Read-only hardlinks; new executable is an independent copy'});write(env..'/package.json',n);print('Fresh binary-only checkpoint: '..target)
