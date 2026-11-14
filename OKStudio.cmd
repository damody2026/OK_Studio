@echo off
setlocal
rem OK Studio (scene editor) from a package: runs in the packaged game (newest Saved\StreetSocial\Build\*.stage) when there is
rem no editor, else like SceneEditor.cmd (Tools\run_scene_editor.lua). Drop a scene file on it to open it.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_scene_editor.lua" -NoBuild %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
exit /b %taskExitCode%
