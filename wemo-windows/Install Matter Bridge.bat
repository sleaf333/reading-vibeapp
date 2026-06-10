@echo off
rem Installs the background task that keeps the Google Home bridge running.
rem Pair with the Google Home app first using "Matter Bridge.bat".
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0matter-bridge\MatterBridgeTask.ps1" install
pause
