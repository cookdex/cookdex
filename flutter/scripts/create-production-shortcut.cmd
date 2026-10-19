@echo off
rem Keep failures visible, including failures before the PowerShell script starts.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Create shortcut.ps1" -NonInteractive
if errorlevel 1 echo Shortcut creation failed. Please report the error shown above.
pause
