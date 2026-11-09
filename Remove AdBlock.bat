@echo off
setlocal
title Statlocker Ad Block - Remove
echo ============================================================
echo    Statlocker Ad Block  -  Remove
echo ============================================================
echo.
echo This removes the ad block. Your hosts file goes back to how it was
echo before (everything else in it is left untouched), and the backup
echo file the installer made is deleted too.
echo.
rem --- Admin check (token-based; "net session" is unreliable on Home/workgroup) ---
powershell -NoProfile -Command "if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 1 }" >nul 2>&1
if not errorlevel 1 goto :admin_ok
echo [1/2] Asking Windows for permission (a window will pop up -
echo       click "Yes". If you click "No", nothing happens.)
echo.
if defined SLK_ELEVATED (
    echo.
    echo The permission step failed twice in a row, so nothing was changed.
    echo Please open an issue on the project's GitHub page and attach
    echo a screenshot of this window.
    echo.
    pause
    exit /b 1
)
set SLK_ELEVATED=1
powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs } catch { Write-Host ('  ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    echo.
    echo Windows permission was not granted, so nothing was changed.
    echo Double-click this file again and click "Yes" to try again.
    echo.
    pause
    exit /b 1
)
echo.
echo A second window will now do the work. You can close this
echo window whenever you like.
pause
exit /b

:admin_ok
echo [1/2] Running with administrator rights - good.
echo.
echo [2/2] Removing the ad block...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0adblock.ps1" remove
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" (
    echo ============================================================
    echo   Done. The ad block is off.
    echo ============================================================
) else (
    echo ============================================================
    echo   Something went wrong (error code %RC%). Try again.
    echo.
    echo   If it keeps failing, your antivirus may be blocking changes
    echo   to the hosts file - check its settings. If not, open an
    echo   issue on the project's GitHub page.
    echo ============================================================
)
echo.
pause
endlocal
