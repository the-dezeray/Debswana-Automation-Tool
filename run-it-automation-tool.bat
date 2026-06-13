@echo off
setlocal
set "TOOLDIR=%~dp0"
:: Strip trailing backslash for cleaner path joins inside PowerShell
if "%TOOLDIR:~-1%"=="\" set "TOOLDIR=%TOOLDIR:~0,-1%"

:: Use 'type' to stream the main script into PowerShell stdin.
:: $ToolDir is set first so the piped script can find apps.json
:: even though it has no $PSScriptRoot of its own.
:: apps.json is just data (not a script), so it is NOT affected
:: by the execution policy that blocks .ps1 files.
(echo $ToolDir = '%TOOLDIR%' & type "it-automation-tool.ps1") | powershell -NoProfile -Command -

pause
