@echo off
setlocal
rem Card reader in UnrealEditor -game (Tools\run_card_reader_development.lua). With the editor it rebuilds OpenKoikatsuEditor
rem first when the shared engine no longer matches this checkout's build; in a package (no editor) it runs in the packaged
rem game (newest Saved\StreetSocial\Build\*.stage) with the package's StreetHeroines cards.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_card_reader_development.lua" %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
if not "%taskExitCode%"=="0" exit /b %taskExitCode%
rem This window stays to watch the game: if it stops responding a line is printed here (where the log and GPU dump are,
rem how to close it yourself); it never closes the game. Set OK_NO_HANG_WATCH=1 to skip, or just close this window.
rem Keep .cmd files ASCII only: with the console in UTF-8 (code page 65001) cmd misreads non-ASCII lines and runs pieces of them.
if "%OK_NO_HANG_WATCH%"=="" "%~dp0Tools\lua\lua.exe" "%~dp0Tools\ok_hang_check.lua" --watch-newest
exit /b %taskExitCode%
