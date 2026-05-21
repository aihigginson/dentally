# Deploy_Cancellation_Reasons.ps1
# Wires Cancellation Reasons through Silver -> Gold -> Fact_Appointments.
#
# Changes deployed:
#   1. Silver.usp_Load_Appointment_Cancellation_Reasons  (was missing from pipeline)
#   2. Audit.Process_Config entries (SILVER_APPOINTMENT_CANCELLATION_REASONS, GOLD_DIM_CANCELLATION_REASONS)
#   3. Gold.Dim_Cancellation_Reasons  (new table + load SP)
#   4. Gold.Fact_Appointments         (new fk_Cancellation_Reason column + updated load SP)
#   5. Audit.usp_Load_All             (new Silver + Gold Dim steps)
#
# After deploy the script runs the data loads in dependency order.

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
Write-Host "`n=== 1. Deploy Silver SP ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Silver.usp_Load_Appointment_Cancellation_Reasons.StoredProcedure.sql" `
            "Silver.usp_Load_Appointment_Cancellation_Reasons"

if ($Errors -gt 0) { Write-Host "`nAborting - deploy failed." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host "`n=== 2. Register Process_Config entries ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
IF NOT EXISTS (SELECT 1 FROM Audit.Process_Config WHERE Process_Code = 'SILVER_APPOINTMENT_CANCELLATION_REASONS')
    INSERT INTO Audit.Process_Config (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
    VALUES ('SILVER_APPOINTMENT_CANCELLATION_REASONS',
            'Silver.usp_Load_Appointment_Cancellation_Reasons',
            'Load Silver.Appointment_Cancellation_Reasons from Bronze.Cancellation_Reasons using MERGE upsert',
            '@Mode = ''LIVE'', @Logging = 1',
            'SILVER', 'PROCEDURE');

IF NOT EXISTS (SELECT 1 FROM Audit.Process_Config WHERE Process_Code = 'GOLD_DIM_CANCELLATION_REASONS')
    INSERT INTO Audit.Process_Config (Process_Code, Process_Name, Process_Desc, Process_Parameters, Process_Category_Code, Process_Type_Code)
    VALUES ('GOLD_DIM_CANCELLATION_REASONS',
            'Gold.usp_Load_Dim_Cancellation_Reasons',
            'Load Gold.Dim_Cancellation_Reasons from Silver layer',
            '@Mode = ''LIVE'', @Logging = 1',
            'GOLD_DIM', 'PROCEDURE');

PRINT 'Process_Config entries: done';
'@
Run-SQL $sql "Audit.Process_Config (2 new entries)"

if ($Errors -gt 0) { Write-Host "`nAborting - deploy failed." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host "`n=== 3. Deploy Gold.Dim_Cancellation_Reasons ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Gold.Dim_Cancellation_Reasons.Table.sql"                      "Gold.Dim_Cancellation_Reasons (table)"
Deploy-File "Gold.usp_Load_Dim_Cancellation_Reasons.StoredProcedure.sql"   "Gold.usp_Load_Dim_Cancellation_Reasons"

if ($Errors -gt 0) { Write-Host "`nAborting - deploy failed." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host "`n=== 4. Deploy Gold.Fact_Appointments (new fk_Cancellation_Reason column) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Gold.Fact_Appointments.Table.sql"                  "Gold.Fact_Appointments (table)"
Deploy-File "Gold.usp_Load_Fact_Appointments.StoredProcedure.sql" "Gold.usp_Load_Fact_Appointments"

if ($Errors -gt 0) { Write-Host "`nAborting - deploy failed." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host "`n=== 5. Deploy Audit.usp_Load_All (new pipeline steps) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Audit.usp_Load_All.sql" "Audit.usp_Load_All"

if ($Errors -gt 0) { Write-Host "`nAborting - deploy failed." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
Write-Host "`n=== 6. Load data ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Load_Appointment_Cancellation_Reasons
     @Mode = 'PROD', @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.Appointment_Cancellation_Reasons  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Silver.usp_Load_Appointment_Cancellation_Reasons"

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Cancellation_Reasons
     @Mode = 'PROD', @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Gold.Dim_Cancellation_Reasons  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Gold.usp_Load_Dim_Cancellation_Reasons"

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_Appointments
     @Mode = 'PROD', @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Gold.Fact_Appointments  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Gold.usp_Load_Fact_Appointments"

# ---------------------------------------------------------------------------
Write-Host "`n$('-' * 60)"
if ($Errors -eq 0) {
    Write-Host "Complete: Cancellation Reasons wired through Silver -> Gold." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. In PBI Desktop: add relationship _Appointments[fk Cancellation Reason]" -ForegroundColor Yellow
    Write-Host "       -> List Cancellation Reasons[pk Cancellation Reason]" -ForegroundColor Yellow
    Write-Host "  2. Update Short Notice Cancellation Rate measure in TabularEditor_HomeDetail.csx" -ForegroundColor Yellow
    Write-Host "       to use RELATED('List Cancellation Reasons'[Is Short Notice])" -ForegroundColor Yellow
} else {
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}
