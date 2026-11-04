@echo off
set "hdmiPython=python"
if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "hdmiPython=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" set "hdmiPython=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
set "hdmiTd=C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td.exe"
if not exist "%hdmiTd%" (
    echo Tang Dynasty executable was not found.
    pause
    exit /b 1
)
"%hdmiPython%" -B "%~dp0tools\prepare_td_project.py" --root "%~dp0." --relocate
if errorlevel 1 (
    echo Project source list or settings are incomplete. No project was opened.
    pause
    exit /b 1
)
"%hdmiPython%" -B "%~dp0tools\fix_td_multiseed.py"
if errorlevel 1 (
    echo MultiSeed path repair failed. No project was opened.
    pause
    exit /b 1
)
"%hdmiPython%" -B "%~dp0tools\td_gui_profile.py" --root "%~dp0." --install
if errorlevel 1 (
    echo Project GUI profile installation failed. No project was opened.
    pause
    exit /b 1
)
start "" "%hdmiTd%" "%~dp0HDMI_media_board_WAV.al"
