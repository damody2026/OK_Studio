@echo off
setlocal
rem Card reader in UnrealEditor -game (Tools\run_card_reader_development.lua). With the editor it rebuilds OpenKoikatsuEditor
rem first when the shared engine no longer matches this checkout's build; in a package (no editor) it runs in the packaged
rem game (newest Saved\StreetSocial\Build\*.stage) with the package's StreetHeroines cards.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_card_reader_development.lua" %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
if not "%taskExitCode%"=="0" exit /b %taskExitCode%
rem 這個視窗留下來盯著遊戲：它沒回應時會在這裡印一行（log 與 GPU dump 在哪、怎麼自己關），不會自動關掉它。
rem 不想要就設 OK_NO_HANG_WATCH=1，或直接關掉這個視窗（不影響遊戲）。
if "%OK_NO_HANG_WATCH%"=="" "%~dp0Tools\lua\lua.exe" "%~dp0Tools\ok_hang_check.lua" --watch-newest
exit /b %taskExitCode%
