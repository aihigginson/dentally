# Deploy_KPI_Snapshot.ps1
# Deploys the updated Gold.usp_Load_Fact_KPI_Snapshot SP (*05) and runs it.
# New metrics added: open_courses (A1), outstanding_invoices (A2),
# active_patients / lapsed_patients / overdue_recalls (A3 accumulating).
# Run this once to populate snapshot data before deploying Part B DAX changes.

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "aihigginson@2rrjxy.onmicrosoft.com"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found. Install the ODBC Driver / sqlcmd tools."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$Errors = 0

function Run-SQL($sql, $label) {
    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tmp, $sql, [System.Text.Encoding]::UTF8)
    Write-Host "  $label" -NoNewline
    & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i $tmp -b
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR" -ForegroundColor Red
        $script:Errors++
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
    Remove-Item $tmp -Force
}

function Deploy-File($file, $label) {
    $path = Join-Path $FabricDir $file
    $sql  = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    Run-SQL $sql $label
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 1. Deploy Gold.usp_Load_Fact_KPI_Snapshot (*05) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Gold.usp_Load_Fact_KPI_Snapshot.StoredProcedure.sql" "Gold.usp_Load_Fact_KPI_Snapshot"

if ($Errors -gt 0) {
    Write-Host ""
    Write-Host "Aborting - SP deploy failed." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 2. Run Gold.usp_Load_Fact_KPI_Snapshot ===" -ForegroundColor Cyan
Write-Host "    This may take a few minutes (3-year weekly + monthly spine x all tenants)."
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_KPI_Snapshot
     @Mode        = 'PROD',
     @Run_Inserts = @i OUT,
     @Run_Updates = @u OUT,
     @Run_Deletes = @d OUT;
PRINT CONCAT('Gold.usp_Load_Fact_KPI_Snapshot  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Gold.usp_Load_Fact_KPI_Snapshot"

if ($Errors -gt 0) {
    Write-Host ""
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 3. Verify snapshot row counts ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
SELECT Metric, COUNT(*) AS Rows, MIN(fk_Date) AS First_fk_Date, MAX(fk_Date) AS Last_fk_Date
FROM Gold.Fact_KPI_Snapshot
GROUP BY Metric
ORDER BY Metric;
'@
Run-SQL $sql "Row counts by metric"

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "------------------------------------------------------------"
if ($Errors -eq 0) {
    Write-Host "Complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Refresh the PBI dataset to pick up new snapshot rows."
    Write-Host "  2. Deploy Part B Tabular Editor scripts to convert DAX measures"
    Write-Host "     (Open Courses, Outstanding Invoices, Active Patients, etc.)"
    Write-Host "     to the snapshot lookup pattern."
    Write-Host "  3. Accumulating metrics (active_patients, lapsed_patients,"
    Write-Host "     overdue_recalls, retention_outlook) will have one row today."
    Write-Host "     Historical trend builds with each weekly SP run."
} else {
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}
