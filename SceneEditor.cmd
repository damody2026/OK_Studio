@echo off
setlocal
set "OK_ALLOW_UNPATCHED_ENGINE=1"
if "%OK_GAME_ROOT%"=="" set "OK_GAME_ROOT=E:/Koikatu"
rem OK Studio scene editor on its own: only the studio UI (Tools\run_scene_editor.lua). Drop a scene file on it to open it.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_scene_editor.lua" -NoBuild %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
exit /b %taskExitCode%
