# Deploy_Journey_Attrs.ps1
# Deploys and runs all objects for the appointment journey attributes feature:
#   - Bronze.usp_Load_Appointments  (full field coverage, adds Booked_Via_API)
#   - Bronze.usp_Load_Recalls       (adds First_Reminder_Sent_At)
#   - Silver.Appointment_Reason_Map (new table + seed data)
#   - Silver.usp_Derive_Appointment_Journey (new SP)
#   - Gold.Fact_Appointments        (table recreated with 4 new journey columns)
#   - Gold.usp_Load_Fact_Appointments
#   - Stage.Appointments view refresh (picks up booked_via_api from Delta)
# Then reloads data: Bronze → Silver → Derive → Gold

param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [Parameter(Mandatory)] [string] $Username
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
Write-Host "`n=== 1. Schema objects ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Deploy-File "Bronze.usp_Load_Appointments.StoredProcedure.sql"     "Bronze.usp_Load_Appointments"
Deploy-File "Bronze.usp_Load_Recalls.StoredProcedure.sql"          "Bronze.usp_Load_Recalls"
Deploy-File "Silver.Appointment_Reason_Map.Table.sql"              "Silver.Appointment_Reason_Map (table)"
Deploy-File "Silver.Appointment_Reason_Map.Data.sql"               "Silver.Appointment_Reason_Map (data)"
Deploy-File "Silver.usp_Derive_Appointment_Journey.StoredProcedure.sql" "Silver.usp_Derive_Appointment_Journey"
Deploy-File "Gold.Fact_Appointments.Table.sql"                     "Gold.Fact_Appointments (DROP/CREATE)"
Deploy-File "Gold.usp_Load_Fact_Appointments.StoredProcedure.sql"  "Gold.usp_Load_Fact_Appointments"

# Recreate the Stage.Appointments view so the new booked_via_api column is visible.
Run-SQL @"
DROP VIEW IF EXISTS [Stage].[Appointments]
GO
CREATE VIEW [Stage].[Appointments] AS SELECT * FROM LH_Dentally.dbo.stage_appointments
GO
"@ "Stage.Appointments (view refresh for booked_via_api)"

if ($Errors -gt 0) {
    Write-Host "`nAborting data reload — $Errors schema error(s) above." -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 2. Get active tenants ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

$tenantOut = & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd `
    -Q "SET NOCOUNT ON; SELECT CAST(Tenant_ID AS VARCHAR(10)) FROM Audit.Tenants WHERE Is_Active = 1;" `
    -h -1 -W 2>&1
$tenantIds = $tenantOut | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_.Trim() }

if ($tenantIds.Count -eq 0) {
    Write-Host "No active tenants found in Audit.Tenants - skipping data reload." -ForegroundColor Yellow
    exit 0
}
Write-Host "  Active tenants: $($tenantIds -join ', ')"

# ---------------------------------------------------------------------------
Write-Host "`n=== 3. Bronze reload (per tenant, full refresh) ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

foreach ($tid in $tenantIds) {
    Run-SQL @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Bronze.usp_Load_Appointments @Tenant_ID = $tid, @Full_Refresh = 1,
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('  Tenant $tid  I=', @i, '  U=', @u, '  D=', @d);
"@ "Bronze.usp_Load_Appointments  tenant $tid"

    Run-SQL @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Bronze.usp_Load_Recalls @Tenant_ID = $tid, @Full_Refresh = 1,
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('  Tenant $tid  I=', @i, '  U=', @u, '  D=', @d);
"@ "Bronze.usp_Load_Recalls      tenant $tid"
}

# ---------------------------------------------------------------------------
Write-Host "`n=== 4. Silver reload ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Run-SQL @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Load_Appointments @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.usp_Load_Appointments  I=', @i, '  U=', @u, '  D=', @d);
"@ "Silver.usp_Load_Appointments"

Run-SQL @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Load_Recalls @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.usp_Load_Recalls  I=', @i, '  U=', @u, '  D=', @d);
"@ "Silver.usp_Load_Recalls"

Run-SQL @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Silver.usp_Derive_Appointment_Journey @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Silver.usp_Derive_Appointment_Journey  I=', @i, '  U=', @u, '  D=', @d);
"@ "Silver.usp_Derive_Appointment_Journey"

# ---------------------------------------------------------------------------
Write-Host "`n=== 5. Gold reload ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

Run-SQL @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_Appointments @Mode = 'PROD',
     @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
PRINT CONCAT('Gold.Fact_Appointments  I=', @i, '  U=', @u, '  D=', @d);
"@ "Gold.usp_Load_Fact_Appointments"

# ---------------------------------------------------------------------------
Write-Host "`n$('-' * 60)"
if ($Errors -eq 0) {
    Write-Host "Complete: all journey attribute objects deployed and data reloaded." -ForegroundColor Green
} else {
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}
