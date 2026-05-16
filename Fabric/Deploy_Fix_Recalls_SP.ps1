# Deploy_Fix_Recalls_SP.ps1
# Deploys the rewritten Silver.usp_Load_Recalls (revision *02) and reloads recalls + journey attrs.
# Fixes: "Invalid column name 'Appointment_ID'" caused by Bronze schema change
# (Recall_Date/Interval_Months/Site_ID/Practitioner_ID).

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "aihigginson@2rrjxy.onmicrosoft.com"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found. Install the ODBC Driver / sqlcmd tools."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

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
    $path = Join-Path $ScriptDir $file
    $sql  = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    Run-SQL $sql $label
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 1. Deploy fixed SP ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Silver.usp_Load_Recalls.StoredProcedure.sql" "Silver.usp_Load_Recalls (schema fix)"

if ($Errors -gt 0) {
    Write-Host "`nAborting - deploy failed." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 2. Reload Silver.Recalls ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Load_Recalls @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.usp_Load_Recalls  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Silver.usp_Load_Recalls"

# ---------------------------------------------------------------------------
Write-Host "`n=== 3. Re-derive appointment journey (uses Recalls.Due_Date) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$sql = @'
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Derive_Appointment_Journey @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.usp_Derive_Appointment_Journey  I=', @i, '  U=', @u, '  D=', @d);
'@
Run-SQL $sql "Silver.usp_Derive_Appointment_Journey"

# ---------------------------------------------------------------------------
Write-Host "`n=== 4. Reload Gold.Fact_Appointments ===" -ForegroundColor Cyan
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
    Write-Host "Complete: Silver.usp_Load_Recalls deployed and data reloaded." -ForegroundColor Green
    Write-Host ""
    Write-Host "NOTE: Silver.Sites (tenants 11-14) still needs fixing separately:" -ForegroundColor Yellow
    Write-Host "  1. Upload updated generate_data.py to LH_Dentally/Files" -ForegroundColor Yellow
    Write-Host "  2. Re-run Seed_Stage_Test_Data notebook (tenants 11-14)" -ForegroundColor Yellow
    Write-Host "  3. Re-run Bronze for tenants 11-14 (Full_Refresh=1)" -ForegroundColor Yellow
    Write-Host "  4. Re-run Silver.usp_Load_Sites" -ForegroundColor Yellow
    Write-Host "  5. Re-run Gold.usp_Load_Dim_Practice_Sites" -ForegroundColor Yellow
} else {
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}
