# ---------------------------------------------------------------------------
#  Capacity_Health.ps1 -- is the shared F4 throttled right now?
# ---------------------------------------------------------------------------
#  ==> A QUERY THAT TOUCHES NO DATA IS THE WHOLE DIAGNOSTIC. <==
#
#  EVALUATE ROW("x", 1) reads nothing, joins nothing and scans nothing, so
#  whatever it takes is admission delay rather than work. Measured on
#  2026-09-28 across one day on this capacity:
#
#      0.3s   healthy
#     20.5s   throttled  (interactive delay, moderate background overage)
#    161.3s   throttled hard, after two full-rebuild releases in 20 minutes
#
#  Every other query sits on top of that floor. That is why a report page
#  firing 30-80 queries reads as "hung", and why a trivial query can look
#  slower than a complex one.
#
#  ==> capacity state = Active IS NOT EVIDENCE OF HEALTH. <== It read Active
#  throughout all three measurements above, including the 161s one. Do not
#  attribute the floor to model reload, RLS or DAX: both workspaces degrade
#  together, which no single model's reload can cause, and a genuine cold
#  load measured 1.0s once the throttle was gone.
#
#  The fix is a suspend/resume, which clears the smoothed carry-forward --
#  but ASK FIRST, it interrupts the live customer. See the RUNBOOK.
#
#  Usage:  .\Scripts\Capacity_Health.ps1
#          .\Scripts\Capacity_Health.ps1 -Quiet    # one line per workspace
#
#  Exit codes:  0 healthy   1 degraded   2 throttled
# ---------------------------------------------------------------------------
param(
    [switch] $Quiet,
    [double] $DegradedSeconds = 2.0,
    [double] $ThrottledSeconds = 10.0
)

$ErrorActionPreference = 'Stop'

$ResourceGroup = 'rg-analytically'
$CapacityName  = 'analytically'
$Workspaces    = @('DEV - DM Dentally', 'DM Dentally')
$DatasetName   = 'PBI Dentally'

# A constant. No table, no column, no measure -- nothing to be slow about.
$Probe = 'EVALUATE ROW("x", 1)'

function Get-PbiHeaders {
    $tok = az account get-access-token --resource "https://analysis.windows.net/powerbi/api" `
                                       --query accessToken -o tsv
    if (-not $tok) { throw "no Power BI token -- run 'az login' first" }
    return @{ Authorization = "Bearer $tok"; 'Content-Type' = 'application/json' }
}

$headers = Get-PbiHeaders

$state = az fabric capacity show --resource-group $ResourceGroup `
                                 --capacity-name $CapacityName --query state -o tsv 2>$null
if (-not $Quiet) {
    Write-Host ""
    Write-Host ("capacity {0} : {1}   (Active is not evidence of health)" -f $CapacityName, $state)
    Write-Host ""
}

$groups = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers $headers).value
$worst  = 0.0

foreach ($wsName in $Workspaces) {
    $ws = $groups | Where-Object { $_.name -eq $wsName }
    if (-not $ws) { Write-Host ("{0,-20} workspace not found" -f $wsName); continue }

    $ds = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($ws.id)/datasets" `
                             -Headers $headers).value | Where-Object { $_.name -eq $DatasetName }
    if (-not $ds) { Write-Host ("{0,-20} dataset not found" -f $wsName); continue }

    $uri  = "https://api.powerbi.com/v1.0/myorg/groups/$($ws.id)/datasets/$($ds.id)/executeQueries"
    $body = @{ queries = @(@{ query = $Probe }) } | ConvertTo-Json -Depth 6

    $sw = [Diagnostics.Stopwatch]::StartNew()
    try   { $null = Invoke-RestMethod -Method Post -Headers $headers -Body $body -Uri $uri; $sw.Stop() }
    catch { $sw.Stop(); Write-Host ("{0,-20} PROBE FAILED after {1:n1}s" -f $wsName, $sw.Elapsed.TotalSeconds); continue }

    $secs = $sw.Elapsed.TotalSeconds
    if ($secs -gt $worst) { $worst = $secs }

    $verdict = if ($secs -ge $ThrottledSeconds) { 'THROTTLED' }
               elseif ($secs -ge $DegradedSeconds) { 'degraded' }
               else { 'healthy' }

    $colour = switch ($verdict) { 'THROTTLED' { 'Red' } 'degraded' { 'Yellow' } default { 'Green' } }

    if ($Quiet) {
        Write-Host ("{0,-20} {1,7:n1}s  {2}" -f $wsName, $secs, $verdict)
    } else {
        $last = (Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/groups/$($ws.id)/datasets/$($ds.id)/refreshes?`$top=1" `
                                   -Headers $headers).value[0]
        Write-Host ("{0,-20} trivial query {1,7:n1}s  " -f $wsName, $secs) -NoNewline
        Write-Host $verdict -ForegroundColor $colour
        Write-Host ("{0,-20}   last refresh {1} {2}" -f '', $last.status, $last.endTime)
    }
}

if (-not $Quiet) {
    Write-Host ""
    if ($worst -ge $ThrottledSeconds) {
        Write-Host "Throttled. A suspend/resume clears the carry-forward -- ASK BEFORE BOUNCING," -ForegroundColor Red
        Write-Host "it interrupts the live customer, and sequence any remaining heavy work first."  -ForegroundColor Red
    } elseif ($worst -ge $DegradedSeconds) {
        Write-Host "Slower than healthy. Usually a cold model load after eviction -- probe again" -ForegroundColor Yellow
        Write-Host "in a moment; if it stays high in BOTH workspaces, it is the capacity."        -ForegroundColor Yellow
    }
    Write-Host ""
}

if     ($worst -ge $ThrottledSeconds) { exit 2 }
elseif ($worst -ge $DegradedSeconds)  { exit 1 }
else                                  { exit 0 }
