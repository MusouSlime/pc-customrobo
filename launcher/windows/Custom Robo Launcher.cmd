@echo off
setlocal
set "PS1=%~dp0CustomRoboLauncher.ps1"
if not exist "%PS1%" set "PS1=%~dp0launcher\windows\CustomRoboLauncher.ps1"
if not exist "%PS1%" (
    echo CustomRoboLauncher.ps1 was not found.
    pause
    exit /b 1
)
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
if errorlevel 1 pause
