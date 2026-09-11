@echo off
rem First-launch shim: seeds the SMS baseline model router if the suite left a
rem pending-seed.json, then hands off to the real AnythingLLM binary. Quiet.
setlocal
set "APPDIR=%~dp0"
set "LAUNCHER=%LOCALAPPDATA%\Programs\AnythingLLM\AnythingLLM.exe"

if not exist "%APPDIR%pending-seed.json" goto launch

powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDIR%scripts\seed-model-router.ps1" -WaitSeconds 120 >nul 2>&1

del "%APPDIR%pending-seed.json" >nul 2>&1

:launch
if exist "%LAUNCHER%" start "" "%LAUNCHER%"
endlocal
