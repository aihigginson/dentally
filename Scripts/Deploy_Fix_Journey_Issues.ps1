# Deploy_Fix_Journey_Issues.ps1
# Deploys the complete Patient_Referrals pipeline and all Sankey column fixes (*03).
# Covers: Stage view, Bronze table + SP, Silver table (with Created_At), Silver load SP,
# Silver.usp_Derive_Appointment_Journey rewrite, then full data reload for all tenants.

param(
    [string]   $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string]   $Database = "WH_Dentally",
    [string]   $Username = "admin@Analytically.info",
    [int[]]    $Tenants  = @(11, 12, 13, 14)
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
    & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i $tmp -b | Out-Null
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
Write-Host "`n=== 1. Stage view ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
BEGIN TRY
    IF OBJECT_ID('[Stage].[Patient_Referrals]', 'V') IS NOT NULL DROP VIEW [Stage].[Patient_Referrals];
    EXEC('CREATE VIEW [Stage].[Patient_Referrals] AS SELECT * FROM LH_Dentally.dbo.stage_patient_referrals');
    PRINT 'Created Stage.Patient_Referrals';
END TRY
BEGIN CATCH
    PRINT 'WARN: Stage.Patient_Referrals skipped -- run Stage_Ingest first';
END CATCH;
'@
Run-SQL $sql "Stage.Patient_Referrals"

if ($Errors -gt 0) {
    Write-Host "`nAborting - Stage view failed (LH_Dentally Delta table not yet ingested)." -ForegroundColor Red
    Write-Host "  1. Upload updated generate_data.py to LH_Dentally/Files" -ForegroundColor Yellow
    Write-Host "  2. Re-run the Stage_Ingest notebook (or Bronze pipeline) to create stage_patient_referrals" -ForegroundColor Yellow
    Write-Host "  3. Re-run this script" -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 2. Bronze -- table + load SP ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Bronze.Patient_Referrals.Table.sql"                    "Bronze.Patient_Referrals (table)"
Deploy-File "Bronze.usp_Load_Patient_Referrals.StoredProcedure.sql" "Bronze.usp_Load_Patient_Referrals"
Deploy-File "Bronze.usp_Load_All.StoredProcedure.sql"               "Bronze.usp_Load_All (updated)"

if ($Errors -gt 0) {
    Write-Host "`nAborting - Bronze schema failed." -ForegroundColor Red; exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 3. Silver -- table (with Created_At), load SP, derive SP ===" -ForegroundColor Cyan
# Silver.Patient_Referrals table must be deployed BEFORE usp_Derive_Appointment_Journey
# because Fabric validates column references at CREATE PROCEDURE time.
# ---------------------------------------------------------------------------

Deploy-File "Silver.Patient_Referrals.Table.sql"                        "Silver.Patient_Referrals (table + Created_At)"
Deploy-File "Silver.usp_Load_Patient_Referrals.StoredProcedure.sql"     "Silver.usp_Load_Patient_Referrals"
Deploy-File "Silver.usp_Derive_Appointment_Journey.StoredProcedure.sql" "Silver.usp_Derive_Appointment_Journey (*03)"

if ($Errors -gt 0) {
    Write-Host "`nAborting - Silver schema failed." -ForegroundColor Red; exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 4. Bronze load -- Patient_Referrals per tenant (Full_Refresh) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$bronzeSqlTpl = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Bronze.usp_Load_Patient_Referrals @Tenant_ID = {0}, @Full_Refresh = 1,
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Bronze.Patient_Referrals  tenant={0}  I=', @i, '  U=', @u, '  D=', @d);
'@
foreach ($tid in $Tenants) {
    Run-SQL ($bronzeSqlTpl -f $tid) "Bronze.usp_Load_Patient_Referrals  tenant=$tid"
}

if ($Errors -gt 0) {
    Write-Host "`nAborting - Bronze load failed." -ForegroundColor Red; exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 5. Silver load -- Patient_Referrals ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Load_Patient_Referrals @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.Patient_Referrals  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Silver.usp_Load_Patient_Referrals"

if ($Errors -gt 0) {
    Write-Host "`nAborting - Silver Patient_Referrals load failed." -ForegroundColor Red; exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 6. Re-derive appointment journey (all four Sankey columns) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Derive_Appointment_Journey @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.usp_Derive_Appointment_Journey  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Silver.usp_Derive_Appointment_Journey"

if ($Errors -gt 0) {
    Write-Host "`nAborting - Journey derivation failed." -ForegroundColor Red; exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 7. Reload Gold.Fact_Appointments ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_Appointments @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Gold.Fact_Appointments  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Gold.usp_Load_Fact_Appointments"

# ---------------------------------------------------------------------------
Write-Host "`n$('-' * 60)"
if ($Errors -eq 0) {
    Write-Host "Complete: all journey fixes deployed and data reloaded." -ForegroundColor Green
    Write-Host ""
    Write-Host "Sankey fixes applied:" -ForegroundColor Green
    Write-Host "  Col 1 Booking:     Online + Referral now populated" -ForegroundColor Green
    Write-Host "  Col 2 This_Visit:  Review codes now in generate_data.py pool" -ForegroundColor Green
    Write-Host "  Col 3 Next_Visit:  Hygiene/Treatment/Review visible (Completed_DT filter removed)" -ForegroundColor Green
    Write-Host "  Col 4 Future_Appt: BBYL + Treatment Booked via separate active_bkg apply" -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: Tenants 1-4 (Railway API) also need updating:" -ForegroundColor Yellow
    Write-Host "  1. Upload updated generate_data.py to Railway" -ForegroundColor Yellow
    Write-Host "  2. Re-trigger Bronze pipeline for tenants 1-4 (Full_Refresh=1)" -ForegroundColor Yellow
    Write-Host "  3. Re-run steps 5-7 above (Silver.usp_Load_Patient_Referrals + Derive + Gold)" -ForegroundColor Yellow
} else {
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}
