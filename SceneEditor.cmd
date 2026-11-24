@echo off
setlocal
set "OK_ALLOW_UNPATCHED_ENGINE=1"
rem No default game folder here: every machine keeps the game somewhere else, so a path written in this file is
rem one machine's and wrong on every other one. Set OK_GAME_ROOT yourself to point at a game; without it the
rem studio opens from the base library alone.
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
