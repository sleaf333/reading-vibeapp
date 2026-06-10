@echo off
rem Runs the Google Home (Matter) bridge in a console window.
rem Use this for the FIRST run so you can scan the pairing QR code with the
rem Google Home app. After pairing, use "Install Matter Bridge.bat" so it
rem runs hidden in the background instead.
cd /d "%~dp0matter-bridge"
where node >nul 2>nul
if errorlevel 1 (
    echo Node.js is required for the Google Home bridge.
    echo Install the LTS version from https://nodejs.org and run this again.
    pause
    exit /b 1
)
if not exist "node_modules\@matter\main" (
    echo Installing bridge dependencies - one time, needs internet...
    call npm install
)
node bridge.js
pause
