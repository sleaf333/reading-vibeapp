# WemoLib.ps1 - shared functions for local Wemo control and dusk/dawn scheduling.
# Works on Windows PowerShell 5.1 (built into Windows 10/11). No internet required.

$script:ConfigDir  = Join-Path $env:APPDATA 'WemoDuskDawn'
$script:ConfigPath = Join-Path $script:ConfigDir 'config.json'
$script:LogPath    = Join-Path $script:ConfigDir 'scheduler.log'
$script:WemoPorts  = @(49153, 49152, 49154, 49155)
$script:TaskName   = 'WemoDuskDawn'

# ---------------------------------------------------------------- config ----

function Get-WemoDefaultConfig {
    [pscustomobject]@{
        zip               = '54313'
        latitude          = 44.5897   # Howard / Green Bay, WI
        longitude         = -88.1218
        twilight          = 'civil'   # official | civil | nautical
        duskOffsetMinutes = 0         # + = later than dusk, - = earlier
        dawnOffsetMinutes = 0
        devices           = @()       # { name, ip, port, automate }
    }
}

function Get-WemoConfig {
    if (Test-Path $script:ConfigPath) {
        try { return (Get-Content $script:ConfigPath -Raw | ConvertFrom-Json) }
        catch { Write-WemoLog "Config unreadable, recreating: $_" }
    }
    $cfg = Get-WemoDefaultConfig
    Save-WemoConfig $cfg
    return $cfg
}

function Save-WemoConfig {
    param([Parameter(Mandatory)]$Config)
    if (-not (Test-Path $script:ConfigDir)) { New-Item -ItemType Directory -Path $script:ConfigDir | Out-Null }
    # Force devices to stay an array even with 0/1 entries
    $Config.devices = @($Config.devices)
    $Config | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ConfigPath -Encoding UTF8
}

function Write-WemoLog {
    param([string]$Message)
    if (-not (Test-Path $script:ConfigDir)) { New-Item -ItemType Directory -Path $script:ConfigDir | Out-Null }
    if ((Test-Path $script:LogPath) -and (Get-Item $script:LogPath).Length -gt 1MB) {
        Get-Content $script:LogPath -Tail 500 | Set-Content $script:LogPath
    }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -Path $script:LogPath
}

# ------------------------------------------------------------ solar math ----
# Sunrise/sunset algorithm from the Almanac for Computers (US Naval Observatory).
# Computed entirely offline from latitude/longitude; no web service needed.

function Get-SunEventLocal {
    param(
        [Parameter(Mandatory)][datetime]$Date,
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][ValidateSet('dawn', 'dusk')][string]$Event
    )
    $zenith = switch ("$($Config.twilight)") {
        'official' { 90.833 }
        'nautical' { 102.0 }
        default    { 96.0 }   # civil twilight = typical "dusk"/"dawn"
    }
    $isRise = ($Event -eq 'dawn')
    $d2r = [math]::PI / 180; $r2d = 180 / [math]::PI
    $lat = [double]$Config.latitude
    $lon = [double]$Config.longitude

    $N = $Date.DayOfYear
    $lngHour = $lon / 15
    if ($isRise) { $t = $N + ((6 - $lngHour) / 24) } else { $t = $N + ((18 - $lngHour) / 24) }

    $M = (0.9856 * $t) - 3.289
    $L = $M + (1.916 * [math]::Sin($M * $d2r)) + (0.020 * [math]::Sin(2 * $M * $d2r)) + 282.634
    $L = (($L % 360) + 360) % 360

    $RA = $r2d * [math]::Atan(0.91764 * [math]::Tan($L * $d2r))
    $RA = (($RA % 360) + 360) % 360
    $RA = ($RA + ([math]::Floor($L / 90) * 90) - ([math]::Floor($RA / 90) * 90)) / 15

    $sinDec = 0.39782 * [math]::Sin($L * $d2r)
    $cosDec = [math]::Cos([math]::Asin($sinDec))
    $cosH = ([math]::Cos($zenith * $d2r) - ($sinDec * [math]::Sin($lat * $d2r))) / ($cosDec * [math]::Cos($lat * $d2r))
    if ($cosH -gt 1 -or $cosH -lt -1) { return $null }  # polar day/night

    if ($isRise) { $H = 360 - ($r2d * [math]::Acos($cosH)) } else { $H = $r2d * [math]::Acos($cosH) }
    $H = $H / 15

    $T = $H + $RA - (0.06571 * $t) - 6.622
    $UT = ((($T - $lngHour) % 24) + 24) % 24

    $utc = [datetime]::SpecifyKind($Date.Date, [DateTimeKind]::Utc).AddHours($UT)
    # The mod-24 wrap can land the UTC value on the wrong day; pick the
    # candidate whose *local* date matches the requested date.
    foreach ($cand in @($utc.AddDays(-1), $utc, $utc.AddDays(1))) {
        $local = [TimeZoneInfo]::ConvertTimeFromUtc($cand, [TimeZoneInfo]::Local)
        if ($local.Date -eq $Date.Date) {
            $offset = if ($isRise) { [int]$Config.dawnOffsetMinutes } else { [int]$Config.duskOffsetMinutes }
            return $local.AddMinutes($offset)
        }
    }
    return $null
}

# Sorted on/off events (dusk -> ON, dawn -> OFF) for a span of days around today.
function Get-ScheduleEvents {
    param([Parameter(Mandatory)]$Config, [int]$DaysBack = 1, [int]$DaysAhead = 2)
    $events = @()
    for ($i = -$DaysBack; $i -le $DaysAhead; $i++) {
        $day = (Get-Date).Date.AddDays($i)
        $dawn = Get-SunEventLocal -Date $day -Config $Config -Event 'dawn'
        $dusk = Get-SunEventLocal -Date $day -Config $Config -Event 'dusk'
        if ($dawn) { $events += [pscustomobject]@{ Time = $dawn; State = 0; Name = 'dawn' } }
        if ($dusk) { $events += [pscustomobject]@{ Time = $dusk; State = 1; Name = 'dusk' } }
    }
    return @($events | Sort-Object Time)
}

# What state should automated switches be in right now? (1 between dusk and dawn)
function Get-ExpectedState {
    param([Parameter(Mandatory)]$Config)
    $past = @(Get-ScheduleEvents -Config $Config | Where-Object { $_.Time -le (Get-Date) })
    if ($past.Count -eq 0) { return $null }
    return $past[-1].State
}

# ----------------------------------------------------------- wemo control ---

function Invoke-WemoSoap {
    param(
        [Parameter(Mandatory)][string]$Ip,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$InnerXml
    )
    $body = @"
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>$InnerXml</s:Body>
</s:Envelope>
"@
    $resp = Invoke-WebRequest -Uri "http://${Ip}:${Port}/upnp/control/basicevent1" `
        -Method Post -Body $body -TimeoutSec 5 -UseBasicParsing `
        -ContentType 'text/xml; charset="utf-8"' `
        -Headers @{ SOAPACTION = "`"urn:Belkin:service:basicevent:1#$Action`"" }
    return $resp.Content
}

# Returns 0 (off), 1 (on), or $null (unreachable). Updates $Device.port on success.
function Get-WemoBinaryState {
    param([Parameter(Mandatory)]$Device)
    $ports = @([int]$Device.port) + ($script:WemoPorts | Where-Object { $_ -ne [int]$Device.port })
    foreach ($p in $ports) {
        try {
            $xml = Invoke-WemoSoap -Ip $Device.ip -Port $p -Action 'GetBinaryState' `
                -InnerXml '<u:GetBinaryState xmlns:u="urn:Belkin:service:basicevent:1"></u:GetBinaryState>'
            if ($xml -match '<BinaryState>(\d+)') {
                $Device.port = $p
                # Insight switches report 8 for "on but in standby"; anything nonzero is on.
                if ([int]$Matches[1] -eq 0) { return 0 } else { return 1 }
            }
        } catch { }
    }
    return $null
}

# Returns $true on success. Tolerates the Wemo quirk of answering "Error"
# when the switch is already in the requested state.
function Set-WemoBinaryState {
    param([Parameter(Mandatory)]$Device, [Parameter(Mandatory)][int]$State)
    $ports = @([int]$Device.port) + ($script:WemoPorts | Where-Object { $_ -ne [int]$Device.port })
    foreach ($p in $ports) {
        try {
            $xml = Invoke-WemoSoap -Ip $Device.ip -Port $p -Action 'SetBinaryState' `
                -InnerXml "<u:SetBinaryState xmlns:u=`"urn:Belkin:service:basicevent:1`"><BinaryState>$State</BinaryState></u:SetBinaryState>"
            $Device.port = $p
            if ($xml -match '<BinaryState>Error') {
                return ((Get-WemoBinaryState -Device $Device) -eq $State)
            }
            return $true
        } catch { }
    }
    return $false
}

# ------------------------------------------------------------- discovery ----

function Get-WemoSetupInfo {
    param([Parameter(Mandatory)][string]$Ip, [int]$Port = 49153)
    try {
        $resp = Invoke-WebRequest -Uri "http://${Ip}:${Port}/setup.xml" -TimeoutSec 4 -UseBasicParsing
        if ($resp.Content -match 'Belkin' -and $resp.Content -match '<friendlyName>(.+?)</friendlyName>') {
            return [pscustomobject]@{ name = $Matches[1].Trim(); ip = $Ip; port = $Port }
        }
    } catch { }
    return $null
}

# SSDP multicast search for Belkin devices on the local network.
function Find-WemoDevices {
    param([int]$TimeoutSeconds = 4)
    $found = @{}
    $udp = New-Object System.Net.Sockets.UdpClient
    try {
        $udp.Client.ReceiveTimeout = 1500
        $search = "M-SEARCH * HTTP/1.1`r`nHOST: 239.255.255.250:1900`r`nMAN: `"ssdp:discover`"`r`nMX: 2`r`nST: urn:Belkin:device:**`r`n`r`n"
        $bytes = [Text.Encoding]::ASCII.GetBytes($search)
        $target = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse('239.255.255.250'), 1900)
        $udp.Send($bytes, $bytes.Length, $target) | Out-Null
        Start-Sleep -Milliseconds 300
        $udp.Send($bytes, $bytes.Length, $target) | Out-Null

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $remote = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        while ((Get-Date) -lt $deadline) {
            try {
                $data = $udp.Receive([ref]$remote)
                $text = [Text.Encoding]::ASCII.GetString($data)
                if ($text -match '(?im)^LOCATION:\s*http://([\d\.]+):(\d+)/') {
                    $ip = $Matches[1]; $port = [int]$Matches[2]
                    if (-not $found.ContainsKey($ip)) {
                        $info = Get-WemoSetupInfo -Ip $ip -Port $port
                        if ($info) { $found[$ip] = $info }
                    }
                }
            } catch { }  # receive timeout -> keep polling until deadline
        }
    } finally { $udp.Close() }
    return @($found.Values)
}

# ------------------------------------------------------------- scheduler ----

# Push the expected schedule state to every automated device (used on startup
# and after the PC wakes from sleep, so missed events get caught up).
function Sync-WemoExpectedState {
    param([Parameter(Mandatory)]$Config)
    $state = Get-ExpectedState -Config $Config
    if ($null -eq $state) { return }
    foreach ($dev in @($Config.devices | Where-Object { $_.automate })) {
        $ok = Set-WemoBinaryState -Device $dev -State $state
        Write-WemoLog ("Sync {0} ({1}) -> {2}: {3}" -f $dev.name, $dev.ip, ($(if ($state) {'ON'} else {'OFF'})), ($(if ($ok) {'ok'} else {'FAILED'})))
    }
    Save-WemoConfig $Config   # persist any learned port changes
}

function Install-WemoSchedulerTask {
    param([Parameter(Mandatory)][string]$ScriptDir)
    $scriptPath = Join-Path $ScriptDir 'WemoScheduler.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Description 'Turns Wemo switches on at dusk and off at dawn (local control).' -Force | Out-Null
    Start-ScheduledTask -TaskName $script:TaskName
}

function Remove-WemoSchedulerTask {
    Stop-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-WemoSchedulerTaskStatus {
    $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) { return 'Not installed' }
    return "Installed ($($task.State))"
}
