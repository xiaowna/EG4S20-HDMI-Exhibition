@echo off
set "hdmiSimPython=python"
if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "hdmiSimPython=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" set "hdmiSimPython=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
"%hdmiSimPython%" -B "%~dp0tools\run_display_sim.py" --scope quick
set "hdmiSimExit=%errorlevel%"
echo.
if "%hdmiSimExit%"=="0" (echo Simulation PASS.) else (echo Simulation FAIL. See reports\display_sim\latest.log.)
pause
exit /b %hdmiSimExit%
