param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [Parameter(Mandatory)] [string] $Username
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$sql = @"
PRINT 'Restoring Tenant_ID=1 data from Gold_Backup to Gold ...'
GO

-- ── Clear Tenant_ID=1 from Gold tables ────────────────────────────────────────
DELETE FROM [Gold].[Aggregate_Site_Patient_Practitioner_Daily] WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Aggregate_Site_Patient_Current]            WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Aggregate_Site_Practitioner_Current]       WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Fact_Recalls]                              WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Dim_Patients]                              WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Dim_Practitioners]                         WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Dim_Practice_Sites]                        WHERE Tenant_ID = 1
GO
DELETE FROM [Gold].[Dim_Tenants]                               WHERE Tenant_ID = 1
GO
DELETE FROM [Input].[Targets]
WHERE Tenant_ID = 1
  AND Period_Type = 'all_time' AND Period_Value = 'all'
  AND Site_ID IS NULL AND Practitioner_ID IS NULL
GO
PRINT '  Cleared existing Tenant_ID=1 rows.'
GO

-- ── Restore from Gold_Backup (non-IDENTITY tables: SELECT * safe) ─────────────
INSERT INTO [Gold].[Dim_Tenants]
SELECT * FROM [Gold_Backup].[Dim_Tenants]
GO
PRINT '  Dim_Tenants: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

INSERT INTO [Gold].[Dim_Practice_Sites]
SELECT * FROM [Gold_Backup].[Dim_Practice_Sites]
GO
PRINT '  Dim_Practice_Sites: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

INSERT INTO [Gold].[Dim_Practitioners]
SELECT * FROM [Gold_Backup].[Dim_Practitioners]
GO
PRINT '  Dim_Practitioners: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

INSERT INTO [Gold].[Dim_Patients]
SELECT * FROM [Gold_Backup].[Dim_Patients]
GO
PRINT '  Dim_Patients: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

INSERT INTO [Gold].[Aggregate_Site_Patient_Practitioner_Daily]
SELECT * FROM [Gold_Backup].[Aggregate_Site_Patient_Practitioner_Daily]
GO
PRINT '  Aggregate_Site_Patient_Practitioner_Daily: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

INSERT INTO [Gold].[Aggregate_Site_Patient_Current]
SELECT * FROM [Gold_Backup].[Aggregate_Site_Patient_Current]
GO
PRINT '  Aggregate_Site_Patient_Current: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

INSERT INTO [Gold].[Aggregate_Site_Practitioner_Current]
SELECT * FROM [Gold_Backup].[Aggregate_Site_Practitioner_Current]
GO
PRINT '  Aggregate_Site_Practitioner_Current: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

-- Fact_Recalls has IDENTITY on pk_Recall — restore without it, let IDENTITY reassign
INSERT INTO [Gold].[Fact_Recalls] (
    Tenant_ID, bk_Recall_ID, fk_Patient,
    fk_Date_Due, fk_Date_Run,
    fk_Date_First_Reminder, fk_Date_Second_Reminder, fk_Date_Last_Reminded,
    Appointment_ID, Recall_Type, Recall_Method,
    Status, Workflow_Status, Workflow_Stage_ID,
    First_Reminder_Type, Second_Reminder_Type, Latest_Reminder_Type,
    Times_Contacted, Due_Date, Run_Date, Days_Overdue,
    DW_Created_At, DW_Updated_At
)
SELECT
    Tenant_ID, bk_Recall_ID, fk_Patient,
    fk_Date_Due, fk_Date_Run,
    fk_Date_First_Reminder, fk_Date_Second_Reminder, fk_Date_Last_Reminded,
    Appointment_ID, Recall_Type, Recall_Method,
    Status, Workflow_Status, Workflow_Stage_ID,
    First_Reminder_Type, Second_Reminder_Type, Latest_Reminder_Type,
    Times_Contacted, Due_Date, Run_Date, Days_Overdue,
    DW_Created_At, DW_Updated_At
FROM [Gold_Backup].[Fact_Recalls]
GO
PRINT '  Fact_Recalls: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

-- Input.Targets has IDENTITY on pk_target — restore without it
INSERT INTO [Input].[Targets] (
    Tenant_ID, Site_ID, Practitioner_ID, Metric,
    Period_Type, Period_Value, Target_Value, Variance,
    DW_Created_At, DW_Updated_At
)
SELECT
    Tenant_ID, Site_ID, Practitioner_ID, Metric,
    Period_Type, Period_Value, Target_Value, Variance,
    DW_Created_At, DW_Updated_At
FROM [Gold_Backup].[Targets]
GO
PRINT '  Input.Targets: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

PRINT 'Restore complete.'
GO
"@

$tmpFile = Join-Path $env:TEMP "Restore_Test_Data_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $sql, [System.Text.Encoding]::UTF8)

Write-Host "Restoring Tenant_ID=1 data into $Database @ $Server ..." -ForegroundColor Cyan
& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE
Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Restore complete. Gold tables have test data." -ForegroundColor Green
} else {
    Write-Host "Restore finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
