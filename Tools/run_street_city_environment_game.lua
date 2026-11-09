-- Actual native game validation; no Editor Python or synthetic clock stepping.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local out=root..'/output/street-social-city-production/day-night-v1'
local mode=arg[1] or 'editor';assert(mode=='editor' or mode=='package' or mode=='pie')
local logic_only=mode=='pie' and os.getenv('STREET_CITY_ENVIRONMENT_NULL_RHI')=='1'
-- An isolated E-engine code host uses the reviewed Content junction and its
-- own freshly compiled plugins, avoiding installation over another Editor.
local project=os.getenv('STREET_CITY_ENVIRONMENT_PROJECT')
if not project then
 local f=io.open(out..'/review-host.json','rb')
 if f then local review=json.decode(f:read('*a'));f:close();if review.status=='passed' and review.engine=='E:/PhysX/UE5.8' then project=review.project end end
end
project=project or root..'/StreetSocialCity/StreetSocialCity.uproject'
project=project:gsub('\\','/')
assert(project==root..'/StreetSocialCity/StreetSocialCity.uproject' or project:match('^E:/StreetSocialCityProduction/environment%-packages/%d+%-%d+/HostProject/StreetSocialCity%.uproject$'),'Unexpected native validation project')
local function read(path)local f=assert(io.open(path,'rb'));local t=f:read('*a');f:close();return json.decode(t)end
local function write(path,data)local t=json.encode(data);local f=assert(io.open(path,'wb'));f:write(t);f:close()end
local function hash(path)
 local script="[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes('"..path:gsub("'","''").."'))).Replace('-','').ToLowerInvariant()"
 local r=ok.proc.run({'powershell.exe','-NoProfile','-Command',script},{capture=true,hide=true});assert(r.code==0,(r.stderr or '')..(r.stdout or ''));return r.stdout:lower():gsub('%s+','')
end
local engine='E:/PhysX/UE5.8'
if mode~='package' then
 local base=project:match('^(.*)/[^/]+$')
 local engine_build=read(engine..'/Engine/Binaries/Win64/UnrealEditor.modules').BuildId
 for _,plugin in ipairs({'CityEnvironment','CityLocalization'}) do
  assert(read(base..'/Plugins/'..plugin..'/Binaries/Win64/UnrealEditor.modules').BuildId==engine_build,'Plugin is not built for the selected E engine: '..plugin)
 end
end
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local before=hash(map)
local config=root..'/StreetSocialCity/Config/DefaultEngine.ini';local config_before=hash(config)
assert(before==read(out..'/current-map.json').map_sha256,'Map changed; reconcile before runtime validation')
local id=mode..'-'..os.date('%Y%m%d-%H%M%S');local receipt=out..'/runtime-'..id..'.json';local log=out..'/runtime-'..id..'.log'
local args={};local launch_env={}
if mode=='editor' or mode=='pie' then args={'E:/PhysX/UE5.8/Engine/Binaries/Win64/UnrealEditor.exe',project,'/Game/UniversityCity/Maps/UniversityCity'}
 if mode=='pie' then
  args[#args+1]='-EnablePlugins=PythonScriptPlugin,EditorScriptingUtilities'
  args[#args+1]='-NoAsyncLoadingThread';args[#args+1]='-NoAsyncPostLoad'
 end
 if mode=='editor' then args[#args+1]='-game' else
  local payload=out..'/runtime-'..id..'-pie-bootstrap.json'
  write(payload,{source=root..'/Tools/run_street_city_environment_game.lua::PIEBootstrap',native_receipt=receipt,code=[=[
import unreal,time,json
from pathlib import Path
unreal.EditorPythonScripting.set_keep_python_script_alive(True)
sub=unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
assert unreal.EditorLevelLibrary.get_editor_world().get_path_name().split('.')[0]=='/Game/UniversityCity/Maps/UniversityCity'
state={'ticks':0,'requested':False,'playing':False,'ending':False,'end_ticks':0,'start':time.monotonic()};native_receipt=Path(PAYLOAD['native_receipt'])
def start_pie(dt):
 state['ticks']+=1
 if state['ticks']<120:return
 if state['ending']:
  if not sub.is_in_play_in_editor():
   state['end_ticks']+=1
   if state['end_ticks']>=30:
    unreal.unregister_slate_post_tick_callback(pie_handle);unreal.log('City native PIE ended before orderly Editor shutdown');unreal.SystemLibrary.quit_editor()
  return
 if sub.is_in_play_in_editor():
  if not state['playing']:state['playing']=True;unreal.log('City native PIE session started; Runtime audit owns remaining checks')
  if state['ticks']%30==0 and native_receipt.is_file():
   try:report=json.loads(native_receipt.read_text('utf-8-sig'))
   except (ValueError,OSError):return
   if report.get('status') in ['passed','failed']:
    assert report.get('external_exit_deferred'), 'PIE Native audit did not defer Editor exit';state['ending']=True;sub.editor_request_end_play()
  return
 if not state['requested']:
  sub.editor_request_begin_play();state['requested']=True;state['request_time']=time.monotonic();unreal.log('City native PIE session requested through LevelEditorSubsystem');return
 if time.monotonic()-state['request_time']>120:
  unreal.unregister_slate_post_tick_callback(pie_handle);unreal.log_error('City PIE did not start within 120 seconds');unreal.SystemLibrary.quit_editor()
pie_handle=unreal.register_slate_post_tick_callback(start_pie)
]=]})
  local helper=root..'/Tools/run_street_city_unreal_deferred.py';args[#args+1]='-ExecutePythonScript='..helper;args[#args+1]='-ScriptErrorsAreFatal';args[#args+1]='-CityEnvironmentAuditExternalExit';launch_env.STREET_CITY_DEFERRED_SCRIPT=helper;launch_env.STREET_CITY_DEFERRED_JSON=payload
 end
else local executable=assert(arg[2],'Pass the exact staged executable');assert(executable:match('^E:/StreetSocialCityProduction/') and executable:match('%.exe$'),'Unexpected staged target');args={executable,'/Game/UniversityCity/Maps/UniversityCity'} end
for _,v in ipairs({'-unattended','-nosplash','-nosound','-windowed','-ResX=1920','-ResY=1080','-NoVSync','-d3d12','-norhithread','-UserDir='..root..'/Saved/StreetSocialCityEnvironmentGameUser','-CityEnvironmentAudit='..receipt,'-abslog='..log,'-ExecCmds=t.MaxFPS 0,r.GPUStatsEnabled 1'}) do args[#args+1]=v end
-- Scope this validation process to a local file store. A DevHttp inherited-
-- context assertion in the Zen request pool must not masquerade as a map pass.
args[#args+1]='-DDC=(Local)';args[#args+1]='-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem'
args[#args+1]='-ini:Engine:[ConsoleVariables]:Editor.AsyncAssetCompilationMaxMemoryUsage=6'
local streetLedger=io.open(out..'/street-surface-install.json','rb');if streetLedger then streetLedger:close();args[#args+1]='-CityEnvironmentStreetLedger='..out..'/street-surface-install.json' end
local tactileLedger=io.open(out..'/tactile-surface-install.json','rb');if tactileLedger then tactileLedger:close();args[#args+1]='-CityEnvironmentTactileLedger='..out..'/tactile-surface-install.json' end
local profile,motion=false,false;for i=2,#arg do if arg[i]=='profile' then profile=true elseif arg[i]=='motion' then motion=true end end;if profile then args[#args+1]='-CityEnvironmentProfile' end;if motion then args[#args+1]='-CityEnvironmentMotion' end
if logic_only then
 assert(not profile and not motion,'NullRHI is for PIE clock/UI logic, not image or GPU validation')
 local filtered={};for _,v in ipairs(args)do if v~='-d3d12' and v~='-norhithread' then filtered[#filtered+1]=v end end
 args=filtered;args[#args+1]='-nullrhi'
end
local result=ok.proc.run(args,{cwd=root,hide=true,env=launch_env,stdout_file=out..'/runtime-'..id..'-stdout.log',stderr_file=out..'/runtime-'..id..'-stderr.log',timeout=1800})
local exists=io.open(receipt,'rb');local report
if exists then exists:close();report=read(receipt) else report={status='failed',error='Native process exited without a receipt'} end
local after=hash(map);local config_after=hash(config)
local profile_ok=not profile or (report.performance and report.performance.target_passed==true)
local expected_pool=tonumber(read(out..'/config-migration.json').after['r.Streaming.PoolSize']);local texture_pool_ok=not expected_pool or report.texture_pool_mb==expected_pool
write(out..'/runtime-'..mode..'-launch.json',{status=result.code==0 and report.status=='passed' and before==after and config_before==config_after and profile_ok and texture_pool_ok and 'passed' or 'failed',run_id=id,engine=engine,project=mode~='package' and project or nil,source_project=root..'/StreetSocialCity/StreetSocialCity.uproject',executable=args[1],exit_code=result.code,native_receipt=receipt,native_receipt_missing=exists==nil,native_log=log,map_sha256=before,map_unchanged=before==after,config_sha256=config_before,config_unchanged=config_before==config_after,renderer=logic_only and 'NullRHI' or 'D3D12',visual_scope=logic_only and 'PIE clock/UI/save-load logic only; visual validation uses the actual staged D3D12 game' or 'Actual rendered runtime',native_ui_screenshot_expected=not logic_only,performance_requested=profile,performance_passed=profile_ok,texture_pool_passed=texture_pool_ok,texture_pool_mb=report.texture_pool_mb,ddc='Local FileSystem only; isolated path',scope='Actual Game world; native UI delegates, real clock ticker, full day at 24x and save/load; optional three-pair same-camera profile A/B'})
assert(result.code==0 and report.status=='passed' and before==after and config_before==config_after and profile_ok and texture_pool_ok,'Native runtime audit failed; inspect '..receipt)
print('City environment '..mode..' runtime passed: '..receipt)
