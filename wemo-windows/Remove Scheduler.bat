@echo off
rem Removes the dusk/dawn background task.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ". '%~dp0WemoLib.ps1'; Remove-WemoSchedulerTask; Write-Host 'Scheduler removed.'"
pause
