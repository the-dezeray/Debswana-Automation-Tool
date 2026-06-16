@echo off
setlocal
set "TOOLDIR=%~dp0"
:: Strip trailing backslash for cleaner path joins inside PowerShell
if "%TOOLDIR:~-1%"=="\" set "TOOLDIR=%TOOLDIR:~0,-1%"

start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%TOOLDIR%\it-automation-tool.ps1"
