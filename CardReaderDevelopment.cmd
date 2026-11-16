@echo off
setlocal
rem Card reader in UnrealEditor -game (Tools\run_card_reader_development.lua). With the editor it rebuilds OpenKoikatsuEditor
rem first when the shared engine no longer matches this checkout's build; in a package (no editor) it runs in the packaged
rem game (newest Saved\StreetSocial\Build\*.stage) with the package's StreetHeroines cards.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_card_reader_development.lua" %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
exit /b %taskExitCode%
