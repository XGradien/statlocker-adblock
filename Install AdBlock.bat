@echo off
setlocal
title Statlocker Ad Block - Install
echo ============================================================
echo    Statlocker Ad Block  -  for the Deadlock Companion App
echo ============================================================
echo.
echo What this does:
echo   * Saves a backup of your Windows hosts file (automatic)
echo   * Blocks the ad networks the Statlocker app talks to
echo   * Does NOT touch the app, your stats, your game, or anything else
echo   * Is 100%% reversible: double-click "Remove AdBlock.bat" anytime
echo.
net session >nul 2>&1
if errorlevel 1 (
    echo [1/2] Asking Windows for permission (a window will pop up -
    echo       click "Yes". If you click "No", nothing happens.)
    echo.
    powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs } catch { Write-Host ('  ' + $_.Exception.Message); exit 1 }"
    if errorlevel 1 (
        echo.
        echo Windows permission was not granted, so nothing was changed.
        echo Double-click this file again and click "Yes" to try again.
        echo.
        pause
        exit /b 1
    )
    exit /b
)
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
    echo   If the app still shows ads, try double-clicking this
    echo   file one more time. If it keeps failing, open an issue
    echo   on the project's GitHub page.
    echo ============================================================
)
echo.
pause
endlocal
