# ---------------------------------------------------------------------------
# Deploy_Template_Config.ps1  --  COPY AND RENAME BEFORE USE
# ---------------------------------------------------------------------------
# New name  : Deploy_vNNN_Description.ps1  (NNN = next sequential number)
# Version   : NNN
# Date      : YYYY-MM-DD
# Author    : AIH
# Layer     : Config / Seed Data
# Changes   : <what changed and why>
# After     : Refresh PBI dataset if metric definitions or targets changed.
#
# Use this template when:
#   - Updating Config.Metric_Definitions, Config.Metric_Period_Types
#   - Updating Audit.Process_Config, Audit.Tenants seed data
#   - Updating Input.Targets or any other MERGE-based seed file
#
# Notes:
#   - All seed files use MERGE -- safe to rerun; no data is wiped.
#   - No SP execution needed; changes take effect immediately on next query.
#   - If metric keys changed, also redeploy Gold.usp_Load_Fact_KPI_Snapshot.
# ---------------------------------------------------------------------------

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "admin@Analytically.info"
)

# ---------------------------------------------------------------------------
# Configuration -- list seed/config files to deploy
# ---------------------------------------------------------------------------

$DeployFiles = @(
    # 'Config.Metric_Definitions.Data.sql'
    # 'Config.Metric_Period_Types.Data.sql'
    # 'Audit.Process_Config.Data.sql'
    # 'Audit.Tenants.Data.sql'
)

# ---------------------------------------------------------------------------

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

if ($DeployFiles.Count -eq 0) {
    Write-Error "No files listed in `$DeployFiles. Fill in the configuration block."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host ""
Write-Host "Deploying config/seed data to $Database @ $Server" -ForegroundColor Cyan

$combined = [System.Text.StringBuilder]::new()
$count = 0

foreach ($file in $DeployFiles) {
    $path = Join-Path $FabricDir $file
    if (-not (Test-Path $path)) { Write-Error "File not found: $path"; exit 1 }
    $null = $combined.AppendLine("PRINT '  FILE: $file';")
    $null = $combined.AppendLine("GO")
    $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
    $null = $combined.AppendLine()
    $count++
}

$tmpFile = Join-Path $env:TEMP "Deploy_Config_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Deploying $count file(s)..."

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. If metric keys or targets changed, refresh the PBI dataset."
    Write-Host "  2. If Process_Config changed, run Audit.usp_Load_All to pick up"
    Write-Host "     new process registrations."
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
    exit 1
}
