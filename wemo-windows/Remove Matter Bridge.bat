@echo off
rem Stops and removes the Google Home bridge background task.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0matter-bridge\MatterBridgeTask.ps1" remove
pause
