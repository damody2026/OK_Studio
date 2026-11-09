-- Explicit, bounded cleanup of superseded local production packages.
-- Never follows directory junctions; keeps source assets and review images.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok')
local mode=arg[1] or 'plan'
assert(mode=='plan' or mode=='apply','Use plan or apply')
local script=[==[
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath('C:\portable\OpenKoikatsu\output\street-social-city-production')
$report='C:\portable\OpenKoikatsu\Saved\ProductionCleanup'
$inventory=Import-Csv -LiteralPath "$report\inventory.csv"
$keep=@('flat-campus-v1\packages\20261024-014032','traffic-v1\packages\20261024-031628','pk0102-floor-v1\packages\20261023-215553','immersion-v1\packages\20261024-150235','immersion-v1\packages\20261024-135124')
$current=Get-Content -LiteralPath "$root\day-night-v1\package.json" -Raw|ConvertFrom-Json
if($current.id -ne '20261024-150235'){throw 'Current package changed; reassess cleanup'}
$runtime=Get-Content -LiteralPath "$root\immersion-v1\runtime-package-launch.json" -Raw|ConvertFrom-Json
if($runtime.status -ne 'passed' -or $runtime.executable -notlike '*20261024-150235*'){throw 'Current validated runtime differs'}
function Assert-Safe([string]$path){
 $full=[IO.Path]::GetFullPath($path)
 if(-not $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Outside cleanup root: $full"}
 $check=$full
 while($check.Length -ge $root.Length){
  if(Test-Path -LiteralPath $check){$item=Get-Item -LiteralPath $check -Force; if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Link boundary: $check"}}
  $check=[IO.Path]::GetDirectoryName($check)
 }
 return $full
}
$candidates=[Collections.Generic.List[object]]::new()
foreach($row in $inventory){
 $relative=$row.Path.Substring($root.Length+1)
 $reason=$null
 if($relative -match '^(flat-campus-v1|traffic-v1|immersion-v1)\\packages\\(\d{8}-\d{6})\\'){
  $package=$Matches[1]+'\packages\'+$Matches[2]
  if($package -notin $keep -and $Matches[2] -lt '20261024-150235'){$reason='Superseded cooked Stage/Archive; newest family package retained'}
 }
 if($relative -match '\.blend[1-9]$'){
  $original=$row.Path -replace '\.blend[1-9]$','.blend'
  if(Test-Path -LiteralPath $original){
   $base=Get-Item -LiteralPath $original
   if($base.Length -gt 0 -and $base.LastWriteTime -ge [datetime]$row.Modified){$reason='Blender automatic backup; newer nonempty .blend retained'}
  }
 }
 if($reason){$null=Assert-Safe $row.Path;$candidates.Add([pscustomobject]@{Path=$row.Path;Bytes=[long]$row.Bytes;Modified=$row.Modified;Reason=$reason})}
}
$candidates|Export-Csv -LiteralPath "$report\delete-plan.csv" -NoTypeInformation -Encoding utf8
$plan=[pscustomobject]@{Root=$root;Files=$candidates.Count;LogicalBytes=($candidates|Measure-Object Bytes -Sum).Sum;RetainedPackages=$keep;CurrentRuntime=$runtime.executable;Mode='__MODE__'}
$plan|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$report\plan.json" -Encoding utf8
if('__MODE__' -eq 'plan'){$plan|ConvertTo-Json -Depth 5;exit 0}
$commands=Get-CimInstance Win32_Process|ForEach-Object {$_.CommandLine}
$packageRoots=$candidates|Where-Object {$_.Reason -like 'Superseded*'}|ForEach-Object {($_.Path -split '\\packages\\')[0]+'\packages\'+(($_.Path -split '\\packages\\')[1] -split '\\')[0]}|Sort-Object -Unique
foreach($p in $packageRoots){foreach($command in $commands){if($command -and ($command.Replace('/','\').IndexOf($p,[StringComparison]::OrdinalIgnoreCase) -ge 0)){throw "Package in use: $p"}}}
$freeBefore=[IO.DriveInfo]::new('C').AvailableFreeSpace
$removed=[Collections.Generic.List[object]]::new();$failed=[Collections.Generic.List[object]]::new()
foreach($row in $candidates){
 try{
  $full=Assert-Safe $row.Path
  $item=Get-Item -LiteralPath $full -Force
  if($item.Length -ne $row.Bytes -or $item.LastWriteTime -ne [datetime]$row.Modified){throw 'Changed after inventory; preserved'}
  Remove-Item -LiteralPath $full -Force -ErrorAction Stop
  $removed.Add($row)
 }catch{$failed.Add([pscustomobject]@{Path=$row.Path;Error=$_.Exception.Message})}
}
$removed|Export-Csv -LiteralPath "$report\deleted.csv" -NoTypeInformation -Encoding utf8
$failed|Export-Csv -LiteralPath "$report\skipped.csv" -NoTypeInformation -Encoding utf8
$deletedSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach($row in $removed){$null=$deletedSet.Add($row.Path)}
$unexpected=[Collections.Generic.List[string]]::new()
foreach($row in $inventory){if(-not $deletedSet.Contains($row.Path) -and -not(Test-Path -LiteralPath $row.Path)){$unexpected.Add($row.Path)}}
$summary=[pscustomobject]@{Status=if($unexpected.Count -eq 0){'passed'}else{'unexpected_missing_files'};DeletedFiles=$removed.Count;DeletedLogicalBytes=($removed|Measure-Object Bytes -Sum).Sum;FreeBefore=$freeBefore;FreeAfter=[IO.DriveInfo]::new('C').AvailableFreeSpace;Skipped=$failed.Count;UnexpectedMissing=@($unexpected);RetainedPackages=$keep;CurrentExecutableExists=(Test-Path -LiteralPath $runtime.executable);Finished=(Get-Date).ToString('o')}
$summary|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$report\result.json" -Encoding utf8
$summary|ConvertTo-Json -Depth 5
if($unexpected.Count -gt 0){exit 1}
]==]
script=script:gsub('__MODE__',mode)
local result=ok.proc.run({'powershell.exe','-NoProfile','-Command',script},{hide=true,capture=true,timeout=3600})
print(result.stdout or '')
if result.stderr and #result.stderr>0 then print(result.stderr)end
assert(result.code==0,'Cleanup failed; inspect Saved/ProductionCleanup')
