# WemoControl.ps1 - Windows GUI for local control of (discontinued) Wemo switches.
# Discover switches on your network, flip them on/off, and enable dusk/dawn
# automation per switch. Launch with "Wemo Control.bat".

. (Join-Path $PSScriptRoot 'WemoLib.ps1')

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:Config  = Get-WemoConfig
$script:Loading = $false
$script:AppDir  = $PSScriptRoot

# ------------------------------------------------------------------ form ----

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Wemo Dusk/Dawn Control'
$form.Size = New-Object System.Drawing.Size(640, 520)
$form.MinimumSize = $form.Size
$form.StartPosition = 'CenterScreen'

$lblSun = New-Object System.Windows.Forms.Label
$lblSun.Location = New-Object System.Drawing.Point(12, 10)
$lblSun.Size = New-Object System.Drawing.Size(600, 20)
$lblSun.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblSun)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Location = New-Object System.Drawing.Point(12, 32)
$lblHint.Size = New-Object System.Drawing.Size(600, 18)
$lblHint.Text = 'Checked switches turn ON at dusk and OFF at dawn (needs the background scheduler installed).'
$form.Controls.Add($lblHint)

$list = New-Object System.Windows.Forms.ListView
$list.Location = New-Object System.Drawing.Point(12, 56)
$list.Size = New-Object System.Drawing.Size(600, 270)
$list.Anchor = 'Top,Left,Right,Bottom'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.CheckBoxes = $true
$list.GridLines = $true
[void]$list.Columns.Add('Auto', 50)
[void]$list.Columns.Add('Switch', 220)
[void]$list.Columns.Add('IP address', 140)
[void]$list.Columns.Add('State', 110)
$form.Controls.Add($list)

$status = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Ready'
[void]$status.Items.Add($statusLabel)
$form.Controls.Add($status)

function New-Button($Text, $X, $Y, $W = 120) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, 30)
    $b.Anchor = 'Bottom,Left'
    $form.Controls.Add($b)
    return $b
}

$btnDiscover = New-Button 'Discover'          12 340
$btnAddIp    = New-Button 'Add by IP...'     138 340
$btnRefresh  = New-Button 'Refresh states'   264 340
$btnRemove   = New-Button 'Remove switch'    390 340
$btnOn       = New-Button 'Turn ON'           12 378
$btnOff      = New-Button 'Turn OFF'         138 378
$btnSync     = New-Button 'Apply schedule now' 264 378 160
$btnInstall  = New-Button 'Install scheduler'  12 416 150
$btnUninstall= New-Button 'Remove scheduler'  168 416 150

$lblTask = New-Object System.Windows.Forms.Label
$lblTask.Location = New-Object System.Drawing.Point(330, 423)
$lblTask.Size = New-Object System.Drawing.Size(290, 20)
$lblTask.Anchor = 'Bottom,Left'
$form.Controls.Add($lblTask)

# --------------------------------------------------------------- helpers ----

function Set-Status($Text) {
    $statusLabel.Text = $Text
    $status.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-SunLabel {
    $dusk = Get-SunEventLocal -Date (Get-Date).Date -Config $script:Config -Event 'dusk'
    $dawn = Get-SunEventLocal -Date (Get-Date).Date -Config $script:Config -Event 'dawn'
    $duskText = if ($dusk) { $dusk.ToString('h:mm tt') } else { 'n/a' }
    $dawnText = if ($dawn) { $dawn.ToString('h:mm tt') } else { 'n/a' }
    $lblSun.Text = "ZIP $($script:Config.zip)  -  Today: dawn $dawnText, dusk $duskText  (computed locally, $($script:Config.twilight) twilight)"
}

function Update-TaskLabel { $lblTask.Text = "Background scheduler: $(Get-WemoSchedulerTaskStatus)" }

function Get-SelectedDevices {
    $items = if ($list.SelectedItems.Count -gt 0) { $list.SelectedItems } else { $list.Items }
    return @($items | ForEach-Object { $_.Tag })
}

function Populate-List {
    param([switch]$QueryStates)
    $script:Loading = $true
    $list.Items.Clear()
    foreach ($dev in @($script:Config.devices)) {
        $item = New-Object System.Windows.Forms.ListViewItem('')
        $item.Checked = [bool]$dev.automate
        [void]$item.SubItems.Add([string]$dev.name)
        [void]$item.SubItems.Add([string]$dev.ip)
        $state = '?'
        if ($QueryStates) {
            Set-Status "Checking $($dev.name)..."
            $s = Get-WemoBinaryState -Device $dev
            $state = if ($null -eq $s) { 'Unreachable' } elseif ($s -eq 1) { 'On' } else { 'Off' }
        }
        [void]$item.SubItems.Add($state)
        $item.Tag = $dev
        [void]$list.Items.Add($item)
    }
    $script:Loading = $false
    if ($QueryStates) { Save-WemoConfig $script:Config; Set-Status 'Ready' }
}

function Merge-Discovered($DiscoveredList) {
    $added = 0
    foreach ($d in @($DiscoveredList)) {
        $existing = @($script:Config.devices) | Where-Object { $_.ip -eq $d.ip } | Select-Object -First 1
        if ($existing) {
            $existing.name = $d.name
            $existing.port = $d.port
        } else {
            $script:Config.devices = @($script:Config.devices) + [pscustomobject]@{
                name = $d.name; ip = $d.ip; port = $d.port; automate = $true
            }
            $added++
        }
    }
    Save-WemoConfig $script:Config
    return $added
}

# ---------------------------------------------------------------- events ----

$list.add_ItemChecked({
    param($s, $e)
    if ($script:Loading) { return }
    $e.Item.Tag.automate = $e.Item.Checked
    Save-WemoConfig $script:Config
})

$btnDiscover.add_Click({
    Set-Status 'Searching the network for Wemo devices (a few seconds)...'
    $found = Find-WemoDevices -TimeoutSeconds 5
    $added = Merge-Discovered $found
    Populate-List -QueryStates
    Set-Status "Discovery done: $(@($found).Count) found, $added new. If a switch is missing, use 'Add by IP...'."
})

$btnAddIp.add_Click({
    $ip = [Microsoft.VisualBasic.Interaction]::InputBox("Enter the switch's IP address (find it in your router's device list):", 'Add Wemo by IP', '192.168.1.')
    if ([string]::IsNullOrWhiteSpace($ip)) { return }
    $ip = $ip.Trim()
    Set-Status "Probing $ip..."
    $info = $null
    foreach ($p in @(49153, 49152, 49154, 49155)) {
        $info = Get-WemoSetupInfo -Ip $ip -Port $p
        if ($info) { break }
    }
    if ($info) {
        [void](Merge-Discovered @($info))
        Populate-List -QueryStates
        Set-Status "Added '$($info.name)' at $ip."
    } else {
        Set-Status "No Wemo found at $ip (is it powered and on the same network?)."
    }
})

$btnRefresh.add_Click({ Populate-List -QueryStates })

$btnRemove.add_Click({
    if ($list.SelectedItems.Count -eq 0) { Set-Status 'Select a switch to remove first.'; return }
    $victims = @($list.SelectedItems | ForEach-Object { $_.Tag.ip })
    $script:Config.devices = @($script:Config.devices | Where-Object { $victims -notcontains $_.ip })
    Save-WemoConfig $script:Config
    Populate-List
    Set-Status 'Removed.'
})

$setState = {
    param([int]$State)
    $devs = Get-SelectedDevices
    if ($devs.Count -eq 0) { Set-Status 'No switches yet - click Discover.'; return }
    foreach ($dev in $devs) {
        Set-Status "Sending $(if ($State) {'ON'} else {'OFF'}) to $($dev.name)..."
        [void](Set-WemoBinaryState -Device $dev -State $State)
    }
    Save-WemoConfig $script:Config
    Populate-List -QueryStates
}
$btnOn.add_Click({ & $setState 1 })
$btnOff.add_Click({ & $setState 0 })

$btnSync.add_Click({
    Set-Status 'Applying current schedule state to automated switches...'
    Sync-WemoExpectedState -Config $script:Config
    Populate-List -QueryStates
    Set-Status 'Schedule state applied (see scheduler.log for details).'
})

$btnInstall.add_Click({
    try {
        Install-WemoSchedulerTask -ScriptDir $script:AppDir
        Set-Status 'Scheduler installed - it starts now and at every sign-in.'
    } catch {
        Set-Status "Install failed: $_ (try running as administrator)"
    }
    Update-TaskLabel
})

$btnUninstall.add_Click({
    Remove-WemoSchedulerTask
    Update-TaskLabel
    Set-Status 'Background scheduler removed.'
})

$form.add_Shown({
    Update-SunLabel
    Update-TaskLabel
    Populate-List
    if (@($script:Config.devices).Count -eq 0) {
        Set-Status "Welcome! Click 'Discover' to find your Wemo switches."
    } else {
        Populate-List -QueryStates
    }
})

[void]$form.ShowDialog()
