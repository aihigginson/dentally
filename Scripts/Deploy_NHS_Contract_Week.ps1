# Deploy_NHS_Contract_Week.ps1
# Deploys the NHS contract weekly UDA target feature:
#   - Fixes Silver.Practitioners.Contract_Targets_String truncation bug
#   - Adds Silver.Practitioner_Contract_Targets table + load SP (OPENJSON)
#   - Adds Is_Working_Day_England to Dim_Date (rebuilds table)
#   - Creates Gold.Fact_NHS_Contract_Week (fk_Practice_Site, fk_Practitioner, Annual_UDA_Target)
#   - Updates Audit.Process_Config and Audit.usp_Load_All

param(
    [string] $Server   = "emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "admin@analytically.info"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
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
Write-Host "=== 1. Fix Silver.Practitioners.Contract_Targets_String (VARCHAR MAX) ===" -ForegroundColor Cyan
# Silver table uses IF NOT EXISTS so ALTER TABLE is needed for existing installs.
# ---------------------------------------------------------------------------
$sql = @'
ALTER TABLE Silver.Practitioners ALTER COLUMN Contract_Targets_String VARCHAR(MAX) NULL;
'@
Run-SQL $sql "ALTER Silver.Practitioners.Contract_Targets_String to VARCHAR(MAX)"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 2. Deploy updated Silver.usp_Load_Practitioners (remove LEFT truncation) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Silver.usp_Load_Practitioners.StoredProcedure.sql" "Silver.usp_Load_Practitioners SP"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 3. Create Silver.Practitioner_Contract_Targets table ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Silver.Practitioner_Contract_Targets.Table.sql" "Silver.Practitioner_Contract_Targets table"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 4. Deploy Silver.usp_Load_Practitioner_Contract_Targets ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Silver.usp_Load_Practitioner_Contract_Targets.StoredProcedure.sql" "Silver.usp_Load_Practitioner_Contract_Targets SP"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 5. Reload Silver.Practitioners (full JSON now flows through) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
$sql = @'
DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0;
EXEC Silver.usp_Load_Practitioners @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT 'Silver.Practitioners updated: ' + CAST(@u AS VARCHAR);
'@
Run-SQL $sql "EXEC Silver.usp_Load_Practitioners"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 6. Populate Silver.Practitioner_Contract_Targets ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
$sql = @'
DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0;
EXEC Silver.usp_Load_Practitioner_Contract_Targets @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT 'Practitioner_Contract_Targets rows: ' + CAST(@i AS VARCHAR);
'@
Run-SQL $sql "EXEC Silver.usp_Load_Practitioner_Contract_Targets"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 7. Deploy Dim_Date table (adds Is_Working_Day_England) ===" -ForegroundColor Cyan
# Fabric validates SP column references at CREATE time so the table must have
# the new column before the SP can be deployed.
# ---------------------------------------------------------------------------
Deploy-File "Gold.Dim_Date.Table.sql" "Gold.Dim_Date table (empty - repopulated in step 9)"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 8. Deploy updated usp_Load_Dim_Date SP ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Gold.usp_Load_Dim_Date.StoredProcedure.sql" "Gold.usp_Load_Dim_Date SP"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 9. Rebuild Dim_Date data ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
$sql = @'
DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0;
EXEC Gold.usp_Load_Dim_Date @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT 'Dim_Date rows: ' + CAST(@i AS VARCHAR);
'@
Run-SQL $sql "EXEC Gold.usp_Load_Dim_Date"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 10. Create Fact_NHS_Contract_Week table ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Gold.Fact_NHS_Contract_Week.Table.sql" "Gold.Fact_NHS_Contract_Week table"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 11. Deploy usp_Load_Fact_NHS_Contract_Week ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Gold.usp_Load_Fact_NHS_Contract_Week.StoredProcedure.sql" "Gold.usp_Load_Fact_NHS_Contract_Week SP"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 12. Populate Fact_NHS_Contract_Week ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
$sql = @'
DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0;
EXEC Gold.usp_Load_Fact_NHS_Contract_Week @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT 'Fact_NHS_Contract_Week rows inserted: ' + CAST(@i AS VARCHAR);
'@
Run-SQL $sql "EXEC Gold.usp_Load_Fact_NHS_Contract_Week"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 13. Update Process_Config and Load_All ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Audit.Process_Config.Data.sql" "Audit.Process_Config data"
Deploy-File "Audit.usp_Load_All.sql"        "Audit.usp_Load_All SP"

# ---------------------------------------------------------------------------
Write-Host ""
if ($Errors -gt 0) {
    Write-Host "Completed with $Errors error(s)." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All steps completed successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Re-run Meta.usp_Create_Gold_Views in Fabric to publish PBI._NHS_Contract_Week view"
    Write-Host "  2. Refresh the NHS semantic model in Power BI"
    Write-Host "  3. Run TabularEditor_NHS.csx in Tabular Editor to add the two new DAX measures"
    Write-Host "  4. Build the line chart in the NHS report:"
    Write-Host "     - X-axis: List Date[Week Commencing Date] filtered to current financial year"
    Write-Host "     - fk_Practitioner = -1 rows: contract obligation line"
    Write-Host "     - fk_Practitioner = N rows: practitioner allocation line"
    Write-Host "     - NHS UDA Claims YTD: actuals line"
}
