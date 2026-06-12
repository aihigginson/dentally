# ---------------------------------------------------------------------------
# Deploy_Template_Cross_Layer.ps1  --  COPY AND RENAME BEFORE USE
# ---------------------------------------------------------------------------
# New name  : Deploy_vNNN_Description.ps1  (NNN = next sequential number)
# Version   : NNN
# Date      : YYYY-MM-DD
# Author    : AIH
# Layer     : Cross-Layer (Bronze -> Silver -> Gold)
# Changes   : <what changed and why>
# After     : Run Fabric pipeline to reload Bronze, then Silver and Gold
#             will reload automatically via Audit.usp_Load_All.
#
# Use this template when:
#   - Adding a new column end-to-end through all layers
#   - Adding a new entity (new Bronze table + Silver table + Gold dim/fact)
#   - Any change that touches more than one layer in sequence
#
# Notes:
#   - Stages abort on error -- fix the stage before continuing.
#   - Deploy order matches medallion dependency: Bronze -> Silver -> Gold -> Config.
#   - Leave a stage's file list empty to skip it.
# ---------------------------------------------------------------------------

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "aihigginson@2rrjxy.onmicrosoft.com"
)

# ---------------------------------------------------------------------------
# Configuration -- fill in files per stage; leave empty arrays to skip
# ---------------------------------------------------------------------------

$Stage1_Bronze = @(
    # 'Bronze.YourEntity.Table.sql'
    # 'Bronze.usp_Load_YourEntity.StoredProcedure.sql'
)

$Stage2_Silver = @(
    # 'Silver.YourEntity.Table.sql'
    # 'Silver.usp_Load_YourEntity.StoredProcedure.sql'
)

$Stage3_Gold = @(
    # 'Gold.YourEntity.Table.sql'
    # 'Gold.usp_Create_YourEntity.StoredProcedure.sql'
    # 'Gold.usp_Load_YourEntity.StoredProcedure.sql'
)

$Stage4_Config = @(
    # 'Audit.Process_Config.Data.sql'
    # 'Config.Metric_Definitions.Data.sql'
)

# ---------------------------------------------------------------------------

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

function Deploy-Stage($label, $files) {
    $active = $files | Where-Object { $_ -ne $null -and $_ -ne '' }
    if (-not $active) {
        Write-Host "  (skipped -- no files)" -ForegroundColor DarkGray
        return $true
    }

    $combined = [System.Text.StringBuilder]::new()
    foreach ($file in $active) {
        $path = Join-Path $FabricDir $file
        if (-not (Test-Path $path)) {
            Write-Error "File not found: $path"
            return $false
        }
        $null = $combined.AppendLine("PRINT '  FILE: $file';")
        $null = $combined.AppendLine("GO")
        $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        $null = $combined.AppendLine()
    }

    $tmp = Join-Path $env:TEMP "Deploy_Stage_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
    [System.IO.File]::WriteAllText($tmp, $combined.ToString(), [System.Text.Encoding]::UTF8)

    & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i $tmp -b
    $rc = $LASTEXITCODE
    Remove-Item $tmp -Force

    if ($rc -ne 0) {
        Write-Host "  FAILED (exit $rc)" -ForegroundColor Red
        return $false
    }
    Write-Host "  OK" -ForegroundColor Green
    return $true
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Cross-layer deploy to $Database @ $Server" -ForegroundColor Cyan
Write-Host "$('─' * 60)"

Write-Host ""
Write-Host "=== Stage 1: Bronze ===" -ForegroundColor Cyan
if (-not (Deploy-Stage "Bronze" $Stage1_Bronze)) {
    Write-Host "Aborting -- fix Bronze stage before continuing." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Stage 2: Silver ===" -ForegroundColor Cyan
if (-not (Deploy-Stage "Silver" $Stage2_Silver)) {
    Write-Host "Aborting -- fix Silver stage before continuing." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Stage 3: Gold ===" -ForegroundColor Cyan
if (-not (Deploy-Stage "Gold" $Stage3_Gold)) {
    Write-Host "Aborting -- fix Gold stage before continuing." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Stage 4: Config / Seed Data ===" -ForegroundColor Cyan
if (-not (Deploy-Stage "Config" $Stage4_Config)) {
    Write-Host "Aborting -- fix Config stage before continuing." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "$('─' * 60)"
Write-Host "Complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. If Bronze tables changed: run Fabric pipeline"
Write-Host "     (Stage_Ingest -> Bronze.usp_Load_All) to repopulate Bronze."
Write-Host "  2. Run Silver usp_Load_* SPs for any changed Silver tables."
Write-Host "  3. Run Gold usp_Load_All (or specific Gold SPs) to rebuild Gold."
Write-Host "  4. Refresh the PBI dataset."
