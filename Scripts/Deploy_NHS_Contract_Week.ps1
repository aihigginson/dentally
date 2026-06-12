# Deploy_NHS_Contract_Week.ps1
# Deploys the NHS contract weekly UDA target feature:
#   - Adds Is_Working_Day_England to Dim_Date (rebuilds table)
#   - Creates Gold.Fact_NHS_Contract_Week table and load SP
#   - Updates Audit.Process_Config and Audit.usp_Load_All
#   - Runs both load SPs to populate data

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
Write-Host "=== 1. Update Dim_Date SP (adds Is_Working_Day_England) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Gold.usp_Load_Dim_Date.StoredProcedure.sql" "Gold.usp_Load_Dim_Date SP"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 2. Rebuild Dim_Date with new column ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
$sql = @"
DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0;
EXEC Gold.usp_Load_Dim_Date @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT 'Dim_Date rows: ' + CAST(@i AS VARCHAR);
"@
Run-SQL $sql "EXEC Gold.usp_Load_Dim_Date"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 3. Create Fact_NHS_Contract_Week table ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Gold.Fact_NHS_Contract_Week.Table.sql" "Gold.Fact_NHS_Contract_Week table"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 4. Deploy usp_Load_Fact_NHS_Contract_Week ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
Deploy-File "Gold.usp_Load_Fact_NHS_Contract_Week.StoredProcedure.sql" "Gold.usp_Load_Fact_NHS_Contract_Week SP"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 5. Populate Fact_NHS_Contract_Week ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------
$sql = @"
DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0;
EXEC Gold.usp_Load_Fact_NHS_Contract_Week @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT 'Fact_NHS_Contract_Week rows inserted: ' + CAST(@i AS VARCHAR);
"@
Run-SQL $sql "EXEC Gold.usp_Load_Fact_NHS_Contract_Week"

if ($Errors -gt 0) { Write-Host "Aborting." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 6. Update Process_Config and Load_All ===" -ForegroundColor Cyan
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
    Write-Host "  1. Re-run Meta.usp_Create_Gold_Views in Fabric to publish the PBI._NHS_Contract_Week view"
    Write-Host "  2. Refresh the NHS semantic model in Power BI"
    Write-Host "  3. Run TabularEditor_NHS.csx in Tabular Editor to add the two new DAX measures"
    Write-Host "  4. Build the line chart visual in the NHS report"
}
