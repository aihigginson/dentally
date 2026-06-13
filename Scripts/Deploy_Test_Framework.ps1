# ---------------------------------------------------------------------------
# Deploy_Test_Framework.ps1
# ---------------------------------------------------------------------------
# Layer   : Test (SQL-side regression framework)
# Purpose : Create the Test schema, tables, seed data and stored procedures.
#           Safe to re-run: tables are DROP/CREATE, seed data is TRUNCATE/INSERT,
#           procedures are DROP/CREATE. Capture_Baseline is recreated empty, so
#           a redeploy resets the baseline -- re-run Test.usp_Promote afterwards
#           if you need to re-establish it.
#
# After   : EXEC Test.usp_Run_Captures @Run_Tag = 'first-run'
#           EXEC Test.usp_Compare           -- review variances
#           EXEC Test.usp_Promote @Release_Tag = 'baseline'   -- bless as baseline
# ---------------------------------------------------------------------------

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "admin@Analytically.info"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

# Deploy order: schema -> tables -> seed data -> procedures.
$Files = @(
    'Test.Schema.sql'
    'Test.Metric_Definition.Table.sql'
    'Test.Comparison_Definition.Table.sql'
    'Test.Capture_Baseline.Table.sql'
    'Test.Capture_Current.Table.sql'
    'Test.Compare_Result.Table.sql'
    'Test.Metric_Definition.Data.sql'
    'Test.Comparison_Definition.Data.sql'
    'Test.usp_Run_Captures.StoredProcedure.sql'
    'Test.usp_Compare.StoredProcedure.sql'
    'Test.usp_Promote.StoredProcedure.sql'
)

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Deploying Test framework to $Database @ $Server" -ForegroundColor Cyan

$combined = [System.Text.StringBuilder]::new()
$count = 0
foreach ($file in $Files) {
    $path = Join-Path $FabricDir $file
    if (-not (Test-Path $path)) {
        Write-Error "File not found: $path"
        exit 1
    }
    $null = $combined.AppendLine("PRINT '  FILE: $file';")
    $null = $combined.AppendLine("GO")
    $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
    $null = $combined.AppendLine()
    $count++
}

$tmpFile = Join-Path $env:TEMP "Deploy_Test_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Combined $count scripts into: $tmpFile"

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host ""
Write-Host ("-" * 60)
if ($rc -eq 0) {
    Write-Host "Complete: Test framework deployed successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. EXEC Test.usp_Run_Captures @Run_Tag = 'first-run'"
    Write-Host "  2. EXEC Test.usp_Compare       (review the two result sets)"
    Write-Host "  3. EXEC Test.usp_Promote @Release_Tag = 'baseline'  (bless as baseline)"
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
