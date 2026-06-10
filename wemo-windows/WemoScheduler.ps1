# WemoScheduler.ps1 - background loop that turns automated Wemo switches
# ON at dusk and OFF at dawn. Runs hidden via the WemoDuskDawn scheduled task.
# All times are computed locally from latitude/longitude - no internet needed.

. (Join-Path $PSScriptRoot 'WemoLib.ps1')

# Only one scheduler instance per user session.
$mutex = New-Object System.Threading.Mutex($false, 'Local\WemoDuskDawnScheduler')
if (-not $mutex.WaitOne(0)) { exit }

Write-WemoLog '--- Scheduler started ---'

# Catch up: if the PC was off/asleep during dusk or dawn, apply the state
# the switches should currently be in.
try {
    $config = Get-WemoConfig
    Sync-WemoExpectedState -Config $config
} catch {
    Write-WemoLog "Startup sync failed: $_"
}

while ($true) {
    try {
        $config = Get-WemoConfig   # re-read so GUI changes take effect
        $next = @(Get-ScheduleEvents -Config $config | Where-Object { $_.Time -gt (Get-Date) }) | Select-Object -First 1
        if ($null -eq $next) {
            Write-WemoLog 'No upcoming sun events (check latitude/longitude); retrying in 1 hour.'
            Start-Sleep -Seconds 3600
            continue
        }

        Write-WemoLog ("Next event: {0} at {1:yyyy-MM-dd h:mm tt} -> {2}" -f $next.Name, $next.Time, ($(if ($next.State) {'ON'} else {'OFF'})))

        # Sleep in short chunks so sleep/hibernate or clock changes can't make
        # us overshoot by more than a couple of minutes.
        while ((Get-Date) -lt $next.Time) {
            $remaining = ($next.Time - (Get-Date)).TotalSeconds
            if ($remaining -le 0) { break }
            Start-Sleep -Seconds ([math]::Min(120, [math]::Max(1, [math]::Ceiling($remaining))))
            # If we slept through the event (laptop lid closed etc.), fall through and fire.
        }

        $config = Get-WemoConfig
        $devices = @($config.devices | Where-Object { $_.automate })
        if ($devices.Count -eq 0) {
            Write-WemoLog 'Event reached but no devices have automation enabled.'
        }
        foreach ($dev in $devices) {
            $ok = $false
            for ($attempt = 1; $attempt -le 3 -and -not $ok; $attempt++) {
                $ok = Set-WemoBinaryState -Device $dev -State $next.State
                if (-not $ok) { Start-Sleep -Seconds (5 * $attempt) }
            }
            Write-WemoLog ("{0}: {1} ({2}) -> {3}: {4}" -f $next.Name, $dev.name, $dev.ip, ($(if ($next.State) {'ON'} else {'OFF'})), ($(if ($ok) {'ok'} else {'FAILED after 3 tries'})))
        }
        Save-WemoConfig $config

        # Step past the event we just handled before recomputing.
        Start-Sleep -Seconds 65
    } catch {
        Write-WemoLog "Scheduler error: $_"
        Start-Sleep -Seconds 300
    }
}
