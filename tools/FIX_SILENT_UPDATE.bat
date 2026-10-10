@echo off
REM ============================================================
REM  Steal a Fish - Silence the auto-updater popup
REM  Double-click this file ONCE. The black window every 5 minutes
REM  goes away; updates keep working silently in the background.
REM  It finds PULL.bat on its own - no need to look for it.
REM ============================================================
setlocal enabledelayedexpansion

set PULL=
REM 1. Fast path: PULL.bat lives in the folder holding this repo.
for %%I in ("%~dp0..") do set TRY=%%~fI\PULL.bat
if exist "!TRY!" set PULL=!TRY!

REM 2. Slow path: ask the scheduled task where IT runs from.
if not defined PULL (
    for /f "delims=" %%A in ('powershell -noprofile -command "$t = Get-ScheduledTask -TaskName 'StealAFishCodeUpdate' -ErrorAction SilentlyContinue; if ($t) { ($t.Actions ^| Select-Object -First 1).Execute }" 2^>nul') do set PULL=%%A
    set PULL=!PULL:"=!
    if defined PULL (
        for %%I in ("!PULL!") do (
            if /i "%%~xI"==".vbs" set PULL=%%~dpIPULL.bat
        )
        set PULL=!PULL:"=!
        if not exist "!PULL!" set PULL=
    )
)

if not defined PULL (
    echo.
    echo  Couldn't find PULL.bat or the updater task.
    echo  Easiest fix: re-run SETUP.bat from the starter kit once,
    echo  then run this file again.
    echo.
    pause
    exit /b 1
)

for %%I in ("!PULL!") do set VBS=%%~dpIPULL_SILENT.vbs

REM Silent launcher: runs PULL.bat with no window at all.
> "!VBS!" echo CreateObject("Wscript.Shell").Run "cmd /c ""!PULL!""", 0, False

schtasks /change /tn "StealAFishCodeUpdate" /tr "wscript.exe \"!VBS!\"" >nul 2>&1
if errorlevel 1 (
    echo.
    echo  Found everything, but couldn't update the task.
    echo  Right-click this file, choose "Run as administrator",
    echo  and double-click it again.
) else (
    echo.
    echo  Done! The updater now runs silently - no more black window.
    echo  Tony's code still lands on its own every few minutes.
)
echo.
pause
