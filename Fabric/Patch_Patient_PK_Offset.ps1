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
-- Shift Tenant_ID=1 seed patient PKs to 1,000,001+ so they cannot collide
-- with ETL-generated PKs from other tenants (which start from 1 via ROW_NUMBER).
-- Also updates every fk_Patient reference that points at these rows.

PRINT 'Checking for duplicate pk_Patient values ...'
GO
SELECT pk_Patient, COUNT(*) AS cnt
FROM Gold.Dim_Patients
GROUP BY pk_Patient
HAVING COUNT(*) > 1
ORDER BY pk_Patient
GO

PRINT 'Shifting Tenant_ID=1 pk_Patient by +1,000,000 ...'
GO
UPDATE Gold.Dim_Patients
SET pk_Patient = pk_Patient + 1000000
WHERE Tenant_ID = 1
GO
PRINT '  Dim_Patients: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows updated'
GO

UPDATE Gold.Aggregate_Site_Patient_Practitioner_Daily
SET fk_Patient = fk_Patient + 1000000
WHERE Tenant_ID = 1
GO
PRINT '  Aggregate_Site_Patient_Practitioner_Daily: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows updated'
GO

UPDATE Gold.Aggregate_Site_Patient_Current
SET fk_Patient = fk_Patient + 1000000
WHERE Tenant_ID = 1
GO
PRINT '  Aggregate_Site_Patient_Current: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows updated'
GO

UPDATE Gold.Fact_Recalls
SET fk_Patient = fk_Patient + 1000000
WHERE Tenant_ID = 1
GO
PRINT '  Fact_Recalls: ' + CAST(@@ROWCOUNT AS VARCHAR) + ' rows updated'
GO

PRINT 'Verifying: duplicate pk_Patient count after patch (should be 0 rows) ...'
GO
SELECT pk_Patient, COUNT(*) AS cnt
FROM Gold.Dim_Patients
GROUP BY pk_Patient
HAVING COUNT(*) > 1
GO

PRINT 'Patch complete.'
GO
"@

$tmpFile = Join-Path $env:TEMP "Patch_Patient_PK_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $sql, [System.Text.Encoding]::UTF8)

Write-Host "Applying patient PK offset patch to $Database @ $Server ..." -ForegroundColor Cyan
& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE
Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Patch complete. Refresh your Power BI model now." -ForegroundColor Green
    Write-Host "Also re-run Backup_Test_Data.ps1 to update the Gold_Backup schema." -ForegroundColor Yellow
} else {
    Write-Host "Patch finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
