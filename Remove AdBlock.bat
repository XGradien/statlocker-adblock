@echo off
setlocal
title Statlocker Ad Block - Remove
echo ============================================================
echo    Statlocker Ad Block  -  Remove
echo ============================================================
echo.
echo This removes the ad block. Your hosts file goes back to exactly
echo how it was before (everything else in it is left untouched).
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
    echo   Something went wrong (error code %RC%). Try again, or
    echo   open an issue on the project's GitHub page.
    echo ============================================================
)
echo.
pause
endlocal
