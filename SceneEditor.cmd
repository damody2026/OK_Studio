@echo off
setlocal
set "OK_ALLOW_UNPATCHED_ENGINE=1"
if "%OK_GAME_ROOT%"=="" set "OK_GAME_ROOT=E:/Koikatu"
rem OK Studio scene editor on its own: only the studio UI (Tools\run_scene_editor.lua). Drop a scene file on it to open it.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\run_scene_editor.lua" -NoBuild %*
set "taskExitCode=%errorlevel%"
if not "%taskExitCode%"=="0" pause
if not "%taskExitCode%"=="0" exit /b %taskExitCode%
rem This window stays to watch the game: if it stops responding a line is printed here (where the log and GPU dump are,
rem how to close it yourself); it never closes the game. Set OK_NO_HANG_WATCH=1 to skip, or just close this window.
rem Keep .cmd files ASCII only: with the console in UTF-8 (code page 65001) cmd misreads non-ASCII lines and runs pieces of them.
if "%OK_NO_HANG_WATCH%"=="" "%~dp0Tools\lua\lua.exe" "%~dp0Tools\ok_hang_check.lua" --watch-newest
exit /b %taskExitCode%
