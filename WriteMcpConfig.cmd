@echo off
setlocal
rem Writes mcp.json here with this folder's absolute paths: the MCP servers an AI client uses to drive the card reader
rem and OK Studio (Tools\write_mcp_config.lua). Run it again after moving the folder.
"%~dp0Tools\lua\lua.exe" "%~dp0Tools\write_mcp_config.lua" %*
set "taskExitCode=%errorlevel%"
pause
exit /b %taskExitCode%
