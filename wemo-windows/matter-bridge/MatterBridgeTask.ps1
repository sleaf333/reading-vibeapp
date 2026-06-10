# MatterBridgeTask.ps1 - install/remove the Windows scheduled task that runs
# the Wemo Matter bridge hidden in the background at every sign-in.
# Usage:  .\MatterBridgeTask.ps1 install   |   .\MatterBridgeTask.ps1 remove

param([Parameter(Position = 0)][ValidateSet('install', 'remove')][string]$Mode = 'install')

$TaskName = 'WemoMatterBridge'

if ($Mode -eq 'remove') {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host 'Matter bridge background task removed.'
    return
}

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) {
    Write-Host 'Node.js was not found. Install it from https://nodejs.org (LTS version), then run this again.'
    exit 1
}

if (-not (Test-Path (Join-Path $PSScriptRoot 'node_modules\@matter\main'))) {
    Write-Host 'Installing bridge dependencies (one time, needs internet)...'
    Push-Location $PSScriptRoot
    npm install
    Pop-Location
}

$bridge = Join-Path $PSScriptRoot 'bridge.js'
$log = Join-Path $env:APPDATA 'WemoDuskDawn\matter-bridge.log'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -WorkingDirectory $PSScriptRoot `
    -Argument "-NoProfile -WindowStyle Hidden -Command `"& '$node' '$bridge' 2>&1 | Out-File -Append '$log'`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Exposes local Wemo switches to Google Home as Matter smart plugs.' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "Matter bridge task installed and started. It runs hidden at every sign-in."
Write-Host "Log file: $log"
