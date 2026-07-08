# =====================================================================
# Capacity.ps1 -- pause / resume the 'analytically' Fabric capacity so you
# only pay for the hours it is actually running (pay-as-you-go billing stops
# while paused; you keep only cheap OneLake storage). Use it pre-revenue:
# resume when you sit down to work, pause when you finish.
#
#   .\Scripts\Capacity.ps1 resume    # start it (before working / demoing)
#   .\Scripts\Capacity.ps1 pause     # stop billing (when you finish)
#   .\Scripts\Capacity.ps1 status    # just check the current state
#
# Needs the Azure CLI logged in (az login) as a capacity admin.
# NOTE: pausing takes BOTH workspaces offline (fine at 0 customers). On resume
# the semantic model cold-loads on the first report open -- that first open is
# a little slow, then normal.
# =====================================================================
param(
    [Parameter(Position = 0)]
    [ValidateSet('pause', 'resume', 'status')]
    [string]$Action = 'status'
)
$ErrorActionPreference = 'Stop'
$rg   = 'rg-analytically'
$name = 'analytically'
$type = 'Microsoft.Fabric/capacities'

function Get-State { (az resource show -g $rg -n $name --resource-type $type --query "properties.state" -o tsv 2>$null) }

$acct = az account show --query name -o tsv 2>$null
if (-not $acct) { Write-Host "Not logged in to Azure CLI. Run:  az login" -ForegroundColor Yellow; exit 1 }

$state = Get-State
if (-not $state) { Write-Host "Could not read capacity '$name' (check az login / permissions)." -ForegroundColor Red; exit 1 }
Write-Host ("Capacity '{0}' is currently: {1}" -f $name, $state)

if ($Action -eq 'status') { return }

if ($Action -eq 'pause') {
    if ($state -in @('Paused', 'Suspended')) { Write-Host "Already paused -- not billing compute." -ForegroundColor Green; return }
    Write-Host "Pausing (stops compute billing) ..."
    az resource invoke-action -g $rg -n $name --resource-type $type --action suspend | Out-Null
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep 5; if ((Get-State) -in @('Paused', 'Suspended')) { break } }
    Write-Host ("State now: {0}. Paused -- only paying cheap OneLake storage." -f (Get-State)) -ForegroundColor Green
}
elseif ($Action -eq 'resume') {
    if ($state -eq 'Active') { Write-Host "Already running." -ForegroundColor Green; return }
    Write-Host "Resuming (starts compute) ..."
    az resource invoke-action -g $rg -n $name --resource-type $type --action resume | Out-Null
    for ($i = 0; $i -lt 40; $i++) { Start-Sleep 5; if ((Get-State) -eq 'Active') { break } }
    Write-Host ("State now: {0}. Running -- reports/warehouse available (model cold-loads on first open)." -f (Get-State)) -ForegroundColor Green
}
