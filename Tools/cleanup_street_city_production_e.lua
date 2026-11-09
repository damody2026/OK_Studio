-- Audited local E-drive generated-output cleanup. Does not traverse junctions.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local mode=arg[1] or 'plan'
assert(mode=='plan' or mode=='apply')
local command=[==[
$ErrorActionPreference='Stop'
$root='E:\StreetSocialCityProduction'
$report='C:\portable\OpenKoikatsu\Saved\ProductionCleanupE'
$rows=Import-Csv -LiteralPath "$report\inventory.csv"
$receipt=Get-Content -LiteralPath 'C:\portable\OpenKoikatsu\output\street-social-city-production\day-night-v1\package.json' -Raw|ConvertFrom-Json
if($receipt.id -ne '20261024-150235' -or $receipt.host -ne 'E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject'){throw 'Current package changed; reassess'}
$keepStages=@('20261023-145531','20261023-213142')
$cookIds=@('20261023-122745','20261023-131556')
$links=Import-Csv -LiteralPath "$report\links.csv"
$roots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$plan=[Collections.Generic.List[object]]::new()
foreach($r in $rows){
 $relative=$r.Path.Substring($root.Length+1);$reason=$null;$target=$null
 if($relative -match '^environment-packages\\(20261023-\d{6})\\(Stage|Archive)\\'){
  $id=$Matches[1];$part=$Matches[2]
  if($part -eq 'Archive' -or $id -notin $keepStages){$target="$root\environment-packages\$id\$part";$reason='Superseded Stage or redundant Archive; two backup Stages retained'}
 }elseif($relative -match '^environment-packages\\(20261023-\d{6})\\Cooked\\'){
  $id=$Matches[1]
  if($id -in $cookIds){$target="$root\environment-packages\$id\Cooked";$reason='Old generated cook cache; current HostProject Saved/Cooked retained'}
 }
 if($reason){$null=$roots.Add($target);$plan.Add([pscustomobject]@{Path=$r.Path;Bytes=[long]$r.Bytes;Modified=$r.Modified;Reason=$reason;Target=$target})}
}
function Assert-DirectoryChain([string]$path){
 $full=[IO.Path]::GetFullPath($path)
 if(-not $full.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Outside allowed root: $full"}
 $check=$full
 while($check.Length -ge $root.Length){
  if(([IO.File]::GetAttributes($check) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Link boundary: $check"}
  $check=[IO.Path]::GetDirectoryName($check)
 }
}
foreach($target in $roots){Assert-DirectoryChain $target}
foreach($link in $links){foreach($target in $roots){if($link.Path.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)){throw "Link inside deletion target: $($link.Path)"}}}
$plan|Export-Csv -LiteralPath "$report\delete-plan.csv" -NoTypeInformation -Encoding utf8
$summary=[pscustomobject]@{Mode='__MODE__';Files=$plan.Count;LogicalBytes=($plan|Measure-Object Bytes -Sum).Sum;Targets=@($roots);KeepStages=$keepStages;KeepCurrentHost=$receipt.host}
$summary|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$report\plan.json" -Encoding utf8
if('__MODE__' -eq 'plan'){$summary|ConvertTo-Json -Depth 5;exit 0}
$commands=Get-CimInstance Win32_Process|ForEach-Object {$_.CommandLine}
foreach($target in $roots){foreach($c in $commands){if($c -and $c.Replace('/','\').IndexOf($target,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "Target in use: $target"}}}
if(Get-CimInstance Win32_Process|Where-Object {$_.Name -match '^(UnrealEditor|UnrealEditor-Cmd|StreetSocialCity|AutomationTool|UnrealPak)\.exe$'}){throw 'Unreal process active; preserve generated cache'}
$freeBefore=[IO.DriveInfo]::new('E').AvailableFreeSpace
$verifiedDirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$deleted=[Collections.Generic.List[object]]::new();$skipped=[Collections.Generic.List[object]]::new()
$writer=[IO.StreamWriter]::new("$report\progress.log",$false)
try{
 foreach($r in $plan){
  try{
   $full=[IO.Path]::GetFullPath($r.Path)
   if(-not $full.StartsWith($r.Target+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Outside fixed deletion target'}
   $parent=[IO.Path]::GetDirectoryName($full)
   if($verifiedDirs.Add($parent)){Assert-DirectoryChain $parent}
   $file=[IO.FileInfo]::new($full)
   if(-not $file.Exists -or $file.Length -ne $r.Bytes -or $file.LastWriteTime -ne [datetime]$r.Modified){throw 'File changed after inventory; preserved'}
   if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'File is link; preserved'}
   Remove-Item -LiteralPath $full -Force -ErrorAction Stop
   $deleted.Add($r)
  }catch{$skipped.Add([pscustomobject]@{Path=$r.Path;Error=$_.Exception.Message})}
  if(($deleted.Count+$skipped.Count)%10000 -eq 0){$writer.WriteLine("Deleted=$($deleted.Count) Skipped=$($skipped.Count)");$writer.Flush()}
 }
}finally{$writer.Dispose()}
$deleted|Export-Csv -LiteralPath "$report\deleted.csv" -NoTypeInformation -Encoding utf8
$skipped|Export-Csv -LiteralPath "$report\skipped.csv" -NoTypeInformation -Encoding utf8
$preservedLinks=[Collections.Generic.List[string]]::new()
foreach($row in $links){$item=Get-Item -LiteralPath $row.Path -Force;if(($item.Target -join '|') -ne $row.Target){$preservedLinks.Add($row.Path)}}
$cLinks=Import-Csv -LiteralPath 'C:\portable\OpenKoikatsu\Saved\ProductionCleanup\links.csv'
$missingSources=[Collections.Generic.List[string]]::new()
foreach($link in $cLinks){if($link.Target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and -not(Test-Path -LiteralPath $link.Target)){$missingSources.Add($link.Target)}}
$result=[pscustomobject]@{Status=if($preservedLinks.Count -eq 0 -and $missingSources.Count -eq 0 -and $skipped.Count -eq 0){'passed'}else{'review_required'};DeletedFiles=$deleted.Count;DeletedLogicalBytes=($deleted|Measure-Object Bytes -Sum).Sum;FreeBefore=$freeBefore;FreeAfter=[IO.DriveInfo]::new('E').AvailableFreeSpace;Skipped=$skipped.Count;ChangedLinks=@($preservedLinks);MissingCLinkedSources=@($missingSources);LinksVerified=$links.Count;Finished=(Get-Date).ToString('o')}
$result|ConvertTo-Json -Depth 5|Set-Content -LiteralPath "$report\result.json" -Encoding utf8
$result|ConvertTo-Json -Depth 5
]==]
command=command:gsub('__MODE__',mode)
local r=ok.proc.run({'powershell.exe','-NoProfile','-Command',command},{hide=true,capture=true,timeout=7200})
print(r.stdout or '');if r.stderr and #r.stderr>0 then print(r.stderr)end
assert(r.code==0,'E-drive cleanup failed; inspect Saved/ProductionCleanupE')
