# =====================================================================
# Capacity.ps1 -- control the 'analytically' Microsoft Fabric capacity to manage cost.
# ONE script, several actions:
#
#   .\Scripts\Capacity.ps1 status    show current SKU + state
#   .\Scripts\Capacity.ps1 resume    start compute (before working / a run)
#   .\Scripts\Capacity.ps1 pause     stop compute billing when idle (keeps only cheap OneLake storage)
#   .\Scripts\Capacity.ps1 f4        scale up to F4 (before a heavy burst, e.g. an onboarding run)
#   .\Scripts\Capacity.ps1 f2        scale back down to F2 (steady state / cheap)
#   .\Scripts\Capacity.ps1 f8        scale to F8 (very heavy one-off)
#
# Typical use:
#   pre-revenue idle day  -> pause when done, resume when working
#   before an onboarding  -> f4 (or f8), run it, then f2 afterwards
#
# Needs the Azure CLI logged in (az login) as a capacity admin. Scaling takes a few minutes
# and reports are briefly unavailable during it. This is Microsoft Fabric (analytics), NOT
# Azure Service Fabric -- no nodes/clusters involved.
# =====================================================================
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'resume', 'pause', 'f2', 'f4', 'f8')]
    [string]$Action = 'status'
)
$ErrorActionPreference = 'Stop'
$rg   = 'rg-analytically'
$name = 'analytically'
$type = 'Microsoft.Fabric/capacities'

function Get-State { (az resource show -g $rg -n $name --resource-type $type --query "properties.state" -o tsv 2>$null) }
function Get-Sku   { (az resource show -g $rg -n $name --resource-type $type --query "sku.name" -o tsv 2>$null) }

$acct = az account show --query name -o tsv 2>$null
if (-not $acct) { Write-Host "Not logged in to Azure CLI. Run:  az login" -ForegroundColor Yellow; exit 1 }

$state = Get-State
if (-not $state) { Write-Host "Could not read capacity '$name' (check az login / permissions)." -ForegroundColor Red; exit 1 }
Write-Host ("Capacity '{0}': {1}, {2}" -f $name, (Get-Sku), $state)

switch ($Action) {
    'status' { return }
    'pause' {
        if ($state -in @('Paused', 'Suspended')) { Write-Host "Already paused -- not billing compute." -ForegroundColor Green; return }
        Write-Host "Pausing (stops compute billing) ..."
        az resource invoke-action -g $rg -n $name --resource-type $type --action suspend | Out-Null
        for ($i = 0; $i -lt 30; $i++) { Start-Sleep 5; if ((Get-State) -in @('Paused', 'Suspended')) { break } }
        Write-Host ("State now: {0}. Paused -- only paying cheap OneLake storage." -f (Get-State)) -ForegroundColor Green
    }
    'resume' {
        if ($state -eq 'Active') { Write-Host "Already running." -ForegroundColor Green; return }
        Write-Host "Resuming (starts compute) ..."
        az resource invoke-action -g $rg -n $name --resource-type $type --action resume | Out-Null
        for ($i = 0; $i -lt 40; $i++) { Start-Sleep 5; if ((Get-State) -eq 'Active') { break } }
        Write-Host ("State now: {0}. Running -- model cold-loads on first report open." -f (Get-State)) -ForegroundColor Green
    }
    default {
        # f2 / f4 / f8 -> resize the SKU
        $sku = $Action.ToUpper()
        if ((Get-Sku) -eq $sku) { Write-Host "Already $sku." -ForegroundColor Green; return }
        if ($state -in @('Paused', 'Suspended')) { Write-Host "Capacity is paused -- run 'resume' before scaling." -ForegroundColor Yellow; return }
        Write-Host "Scaling to $sku (a few minutes; reports briefly unavailable) ..."
        az resource update -g $rg -n $name --resource-type $type --set sku.name=$sku | Out-Null
        Write-Host ("SKU now: {0}, {1}." -f (Get-Sku), (Get-State)) -ForegroundColor Green
    }
}
