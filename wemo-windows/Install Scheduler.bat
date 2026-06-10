@echo off
rem Installs the background task that fires at dusk/dawn (also available from the app).
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ". '%~dp0WemoLib.ps1'; Install-WemoSchedulerTask -ScriptDir '%~dp0.'; Write-Host 'Scheduler installed:' (Get-WemoSchedulerTaskStatus)"
pause
