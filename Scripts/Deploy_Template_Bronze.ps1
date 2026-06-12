# ---------------------------------------------------------------------------
# Deploy_Template_Bronze.ps1  --  COPY AND RENAME BEFORE USE
# ---------------------------------------------------------------------------
# New name  : Deploy_vNNN_Description.ps1  (NNN = next sequential number)
# Version   : NNN
# Date      : YYYY-MM-DD
# Author    : AIH
# Layer     : Bronze
# Changes   : <what changed and why>
# After     : Run Fabric pipeline (Stage_Ingest -> Bronze.usp_Load_All)
#             to repopulate Bronze from lakehouse data.
#
# Use this template when:
#   - Changing a Bronze table schema (add/remove/rename column)
#   - Updating a Bronze usp_Load_* stored procedure
#   - Both together (most common case)
#
# Notes:
#   - Include Bronze.usp_Load_All if Process_Config changed (new entity).
#   - Include Audit.Process_Config.Data.sql if adding a new process row.
#   - If ONLY updating a SP (no table change), use Deploy_Quick.ps1 instead.
# ---------------------------------------------------------------------------

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "aihigginson@2rrjxy.onmicrosoft.com"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$Groups = [ordered]@{

    '06. Bronze tables' = @(
        # List table DDL files to (re)deploy. Drop/create semantics -- data is wiped.
        # 'Bronze.YourEntity.Table.sql'
    )

    '07. Bronze stored procedures' = @(
        # 'Bronze.usp_Load_YourEntity.StoredProcedure.sql'
        # Include usp_Load_All only if the orchestration list changed:
        # 'Bronze.usp_Load_All.StoredProcedure.sql'
    )

    '08. Process Config' = @(
        # Include only if a new process row was added to Process_Config:
        # 'Audit.Process_Config.Data.sql'
    )
}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host ""
Write-Host "Deploying Bronze fix to $Database @ $Server" -ForegroundColor Cyan

$combined = [System.Text.StringBuilder]::new()
$count = 0

foreach ($group in $Groups.GetEnumerator()) {
    $files = $group.Value | Where-Object { $_ -ne $null -and $_ -ne '' }
    if (-not $files) { continue }
    $null = $combined.AppendLine("PRINT '>>> GROUP: $($group.Key)';")
    $null = $combined.AppendLine("GO")
    foreach ($file in $files) {
        $path = Join-Path $FabricDir $file
        if (-not (Test-Path $path)) { Write-Error "File not found: $path"; exit 1 }
        $null = $combined.AppendLine("PRINT '  FILE: $file';")
        $null = $combined.AppendLine("GO")
        $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        $null = $combined.AppendLine()
        $count++
    }
}

if ($count -eq 0) {
    Write-Error "No files to deploy. Fill in the Groups hashtable."
    exit 1
}

$tmpFile = Join-Path $env:TEMP "Deploy_Bronze_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
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
    Write-Host "  1. Run Fabric pipeline: Stage_Ingest -> Bronze.usp_Load_All"
    Write-Host "     to repopulate Bronze tables from lakehouse Delta data."
    Write-Host "  2. If Silver or Gold SPs reference the changed column,"
    Write-Host "     use Deploy_Template_Silver.ps1 / Deploy_Template_Gold.ps1 next."
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
    exit 1
}
