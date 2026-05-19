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
-- Create backup schema
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Gold_Backup')
    EXEC('CREATE SCHEMA Gold_Backup')
GO

PRINT 'Backing up Tenant_ID=1 data to Gold_Backup schema ...'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Dim_Tenants]
GO
SELECT * INTO [Gold_Backup].[Dim_Tenants]
FROM [Gold].[Dim_Tenants] WHERE Tenant_ID = 1
GO
PRINT '  Dim_Tenants: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Dim_Practice_Sites]
GO
SELECT * INTO [Gold_Backup].[Dim_Practice_Sites]
FROM [Gold].[Dim_Practice_Sites] WHERE Tenant_ID = 1
GO
PRINT '  Dim_Practice_Sites: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Dim_Practitioners]
GO
SELECT * INTO [Gold_Backup].[Dim_Practitioners]
FROM [Gold].[Dim_Practitioners] WHERE Tenant_ID = 1
GO
PRINT '  Dim_Practitioners: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Dim_Patients]
GO
SELECT * INTO [Gold_Backup].[Dim_Patients]
FROM [Gold].[Dim_Patients] WHERE Tenant_ID = 1
GO
PRINT '  Dim_Patients: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Aggregate_Site_Patient_Practitioner_Daily]
GO
SELECT * INTO [Gold_Backup].[Aggregate_Site_Patient_Practitioner_Daily]
FROM [Gold].[Aggregate_Site_Patient_Practitioner_Daily] WHERE Tenant_ID = 1
GO
PRINT '  Aggregate_Site_Patient_Practitioner_Daily: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Aggregate_Site_Patient_Current]
GO
SELECT * INTO [Gold_Backup].[Aggregate_Site_Patient_Current]
FROM [Gold].[Aggregate_Site_Patient_Current] WHERE Tenant_ID = 1
GO
PRINT '  Aggregate_Site_Patient_Current: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Aggregate_Site_Practitioner_Current]
GO
SELECT * INTO [Gold_Backup].[Aggregate_Site_Practitioner_Current]
FROM [Gold].[Aggregate_Site_Practitioner_Current] WHERE Tenant_ID = 1
GO
PRINT '  Aggregate_Site_Practitioner_Current: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Fact_Recalls]
GO
SELECT * INTO [Gold_Backup].[Fact_Recalls]
FROM [Gold].[Fact_Recalls] WHERE Tenant_ID = 1
GO
PRINT '  Fact_Recalls: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

DROP TABLE IF EXISTS [Gold_Backup].[Targets]
GO
SELECT * INTO [Gold_Backup].[Targets]
FROM [Input].[Targets]
WHERE Tenant_ID = 1
  AND Period_Type = 'all_time' AND Period_Value = 'all'
  AND Site_ID IS NULL AND Practitioner_ID IS NULL
GO
PRINT '  Input.Targets: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows'
GO

PRINT 'Backup complete.'
GO
"@

$tmpFile = Join-Path $env:TEMP "Backup_Test_Data_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $sql, [System.Text.Encoding]::UTF8)

Write-Host "Backing up Tenant_ID=1 data from $Database @ $Server ..." -ForegroundColor Cyan
& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE
Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Backup complete. Data is in Gold_Backup schema." -ForegroundColor Green
} else {
    Write-Host "Backup finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
