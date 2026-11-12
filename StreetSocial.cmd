@echo off
setlocal
rem University city (the new map; the old built street is no longer played): one male and the player-selected APNG female NPCs (Tools\run_street_social_development.lua).
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_street_social_development.lua" %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
exit /b %taskExitCode%
