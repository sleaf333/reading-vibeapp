@echo off
rem Launches the Wemo Dusk/Dawn control window.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0WemoControl.ps1"
