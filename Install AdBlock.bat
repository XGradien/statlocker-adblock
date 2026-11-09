@echo off
setlocal
title Statlocker Ad Block - Install
echo ============================================================
echo    Statlocker Ad Block  -  for the Deadlock Companion App
echo ============================================================
echo.
echo What this does:
echo   * Saves a backup of your Windows hosts file (automatic, and
echo     deleted again when you remove the block)
echo   * Blocks the ad networks the Statlocker app talks to
echo   * Does NOT touch the app, your stats, your game, or anything else
echo   * Is 100%% reversible: double-click "Remove AdBlock.bat" anytime
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
echo [2/2] Installing the ad block...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0adblock.ps1" install
set RC=%ERRORLEVEL%
echo.
if "%RC%"=="0" (
    echo ============================================================
    echo   Done! Now quit the Statlocker app and start it again.
    echo   The ads will be gone.
    echo ============================================================
) else (
    echo ============================================================
    echo   Something went wrong (error code %RC%).
    echo   Try double-clicking this file one more time.
    echo.
    echo   If it keeps failing, your antivirus may be blocking changes
    echo   to the hosts file - check its settings. If not, open an
    echo   issue on the project's GitHub page.
    echo ============================================================
)
echo.
pause
endlocal
