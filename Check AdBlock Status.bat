@echo off
setlocal
title Statlocker Ad Block - Status
echo ============================================================
echo    Statlocker Ad Block  -  Status
echo ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0adblock.ps1" status
echo.
pause
endlocal
