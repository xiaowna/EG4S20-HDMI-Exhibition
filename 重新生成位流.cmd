@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_td.ps1" -Action Build
set "hdmiBuildExit=%errorlevel%"
if not "%hdmiBuildExit%"=="0" echo Build failed. Check reports\td_build_latest.log.
pause
exit /b %hdmiBuildExit%
