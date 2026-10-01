@echo off
rem First-launch shim: hands off to the real AnythingLLM binary, then seeds the
rem SMS baseline model router once the app has created its db (seeder polls).
rem Pending seed is consumed only after the seed actually applied; kept for the
rem next launch otherwise. Quiet.
setlocal
set "APPDIR=%~dp0"
set "LAUNCHER=%LOCALAPPDATA%\Programs\AnythingLLM\AnythingLLM.exe"

rem Launch first: the seeder waits for the db that this launch creates.
if exist "%LAUNCHER%" (
  start "" "%LAUNCHER%"
) else (
  rem Nothing to launch: do not consume the pending seed on a dead end.
  exit /b 0
)

if exist "%APPDIR%pending-seed.json" (
  rem The ps1 polls for the db, closes the app, seeds db + .env (key injection),
  rem relaunches the app, and consumes the pending marker itself on success.
  rem If seeding fails the marker survives for the next launch to retry.
  powershell -NoProfile -ExecutionPolicy Bypass -File "%APPDIR%scripts\seed-model-router.ps1" -WaitSeconds 120 >nul 2>&1
)

endlocal
