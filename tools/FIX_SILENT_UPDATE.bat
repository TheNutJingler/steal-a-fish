@echo off
REM ============================================================
REM  Steal a Fish - Silence the auto-updater popup
REM  Double-click this file ONCE. The black window every 5 minutes
REM  goes away; updates keep working silently in the background.
REM ============================================================
setlocal
for %%I in ("%~dp0..") do set ROOT=%%~fI
set PULL=%ROOT%\PULL.bat
set VBS=%ROOT%\PULL_SILENT.vbs

if not exist "%PULL%" (
    echo.
    echo  Couldn't find PULL.bat in %ROOT%
    echo  Nothing changed.
    pause
    exit /b 1
)

REM Silent launcher: runs PULL.bat with no window at all.
> "%VBS%" echo CreateObject("Wscript.Shell").Run "cmd /c ""%PULL%""", 0, False

schtasks /change /tn "StealAFishCodeUpdate" /tr "wscript.exe \"%VBS%\"" >nul 2>&1
if errorlevel 1 (
    echo.
    echo  Couldn't update the task. Right-click this file,
    echo  choose "Run as administrator", and double-click again.
) else (
    echo.
    echo  Done! The updater now runs silently - no more black window.
    echo  Tony's code still lands on its own every few minutes.
)
echo.
pause
