@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -File "%~dp0NEO-X-Server.ps1"
pause
