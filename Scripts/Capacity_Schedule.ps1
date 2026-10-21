# =====================================================================
# Capacity_Schedule.ps1 -- hold the 'analytically' Fabric capacity at the SKU the
# time of day calls for. Pre-revenue, the capacity is the largest line on the bill
# and it does not need to be F4 while nobody is looking at it.
#
#   .\Scripts\Capacity_Schedule.ps1            apply the schedule for right now
#   .\Scripts\Capacity_Schedule.ps1 -WhatIf    say what it would do, change nothing
#   .\Scripts\Capacity_Schedule.ps1 -At '23:30'   test a particular UK local time
#
# ==> THE SCHEDULE IS IN UK LOCAL TIME, NOT UTC. <== The Fabric pipeline is scheduled
# in UK local time (it logs 21:03 UTC through BST, i.e. 22:03 at home), so the window
# that protects the nightly build has to move with the clocks or it will miss the
# build by an hour every winter. Everything below works in Europe/London and converts
# only at the edges. A caller firing this on a UTC cron therefore fires it at the
# union of both offsets' boundary hours and lets the comparison below no-op the
# half that is not due -- which also means a failed scale is retried an hour later
# rather than leaving the capacity stuck on the wrong SKU until someone notices.
#
# Each row is "from this UK local hour, run at this SKU, until the next row".
# 'pause' is a legal value: it stops compute billing entirely, which is worth far
# more than F2 overnight. Nothing runs between 23:00 and 07:00 UK -- measured over
# 14 days in Audit.Process_Execution_Log, the hour histogram is empty there -- so
# swapping the 00:00 row to 'pause' is a change of one word when you want it.
# =====================================================================
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$At,                       # UK local 'HH:mm' to evaluate instead of now
    [int]$LeadMinutes = 0,             # look this far ahead, so a scale LANDS on the boundary
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'

$rg   = 'rg-analytically'
$name = 'analytically'
$type = 'Microsoft.Fabric/capacities'

# "from this UK local hour, hold this SKU, until the next row."
# ==> NOT AN ORDERED DICTIONARY. <== Indexing one with an integer is POSITIONAL in
# PowerShell, not a key lookup, so $schedule[8] asks for the ninth element and gets
# nothing -- every hour after 08:00 silently resolved to an empty SKU. A list of rows
# cannot be read the wrong way.
$schedule = @(
    @{ From = 0;  Sku = 'pause' }  # nothing is scheduled between 23:00 and 07:00
    @{ From = 6;  Sku = 'F2' }     # early, in case somebody is up before the day starts
    @{ From = 8;  Sku = 'F4' }     # working day
    @{ From = 18; Sku = 'F2' }     # evening
    @{ From = 22; Sku = 'F4' }     # the nightly build -- 22:03 to about 22:37 UK
)

function Get-UkNow {
    # ==> LOOK SLIGHTLY AHEAD, SO THE CHANGE LANDS ON THE BOUNDARY RATHER THAN AFTER IT. <==
    # Resuming a paused capacity takes a couple of minutes and a resize takes a few more,
    # and a GitHub cron does not fire to the second. Running a little early and asking
    # "what should be true shortly?" means 08:00 finds the capacity already on F4, instead
    # of starting the climb then. The caller fires correspondingly early.
    if ($At) {
        $t = [datetime]::ParseExact($At, 'HH:mm', $null)
        return (Get-Date -Hour $t.Hour -Minute $t.Minute -Second 0).AddMinutes($LeadMinutes)
    }
    # 'Europe/London' on Linux, 'GMT Standard Time' on Windows -- the agent may be either.
    foreach ($id in 'Europe/London', 'GMT Standard Time') {
        try { $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($id); break } catch { }
    }
    if (-not $tz) { throw 'Could not resolve the UK time zone on this agent.' }
    [System.TimeZoneInfo]::ConvertTimeFromUtc([datetime]::UtcNow, $tz).AddMinutes($LeadMinutes)
}

function Get-Target([int]$hour) {
    $pick = $null
    foreach ($row in $schedule) { if ($hour -ge $row.From) { $pick = $row.Sku } }
    # before the first row of the day, the previous day's last window still applies
    if (-not $pick) { $pick = $schedule[-1].Sku }
    $pick
}

$now    = Get-UkNow
$target = Get-Target $now.Hour

if (-not (az account show --query name -o tsv 2>$null)) {
    Write-Host 'Not logged in to Azure CLI (az login, or azure/login in CI).' -ForegroundColor Red
    exit 1
}

$state = az resource show -g $rg -n $name --resource-type $type --query 'properties.state' -o tsv 2>$null
$sku   = az resource show -g $rg -n $name --resource-type $type --query 'sku.name'         -o tsv 2>$null
if (-not $state) {
    Write-Host "Could not read capacity '$name' -- check the login has rights on $rg." -ForegroundColor Red
    exit 1
}

$stamp = $now.ToString('ddd HH:mm')
Write-Host ("{0} UK -> target {1}; capacity is {2}, {3}" -f $stamp, $target, $sku, $state)

# ---- pause / resume ---------------------------------------------------------
if ($target -eq 'pause') {
    if ($state -in @('Paused', 'Suspended')) { if (-not $Quiet) { Write-Host 'Already paused.' -ForegroundColor Green }; exit 0 }
    if ($PSCmdlet.ShouldProcess($name, 'suspend')) {
        az resource invoke-action -g $rg -n $name --resource-type $type --action suspend | Out-Null
        Write-Host 'Paused -- compute billing stopped.' -ForegroundColor Green
    }
    exit 0
}

# ==> A PAUSED CAPACITY CANNOT BE RESIZED, SO RESUME FIRST AND SCALE AFTER. <==
if ($state -in @('Paused', 'Suspended')) {
    if ($PSCmdlet.ShouldProcess($name, 'resume')) {
        Write-Host 'Capacity is paused and the schedule wants it running -- resuming ...'
        az resource invoke-action -g $rg -n $name --resource-type $type --action resume | Out-Null
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep 5
            if ((az resource show -g $rg -n $name --resource-type $type --query 'properties.state' -o tsv 2>$null) -eq 'Active') { break }
        }
        $sku = az resource show -g $rg -n $name --resource-type $type --query 'sku.name' -o tsv 2>$null
    }
}

# ---- resize -----------------------------------------------------------------
if ($sku -eq $target) {
    if (-not $Quiet) { Write-Host "Already $target -- nothing to do." -ForegroundColor Green }
    exit 0
}

if ($PSCmdlet.ShouldProcess($name, "scale $sku -> $target")) {
    Write-Host "Scaling $sku -> $target (reports are briefly unavailable during the change) ..."
    az resource update -g $rg -n $name --resource-type $type --set "sku.name=$target" | Out-Null
    $after = az resource show -g $rg -n $name --resource-type $type --query 'sku.name' -o tsv 2>$null
    if ($after -ne $target) {
        Write-Host "Scale did not take: still $after." -ForegroundColor Red
        exit 1
    }
    Write-Host "SKU now $after." -ForegroundColor Green
}
