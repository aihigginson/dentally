# Deploy_Targets_Update.ps1
# Deploys the targets architecture updates:
#   - Dim_Date: Financial_Year_Name format changed to 'FY 2025-26'
#   - Fact_Daily_Targets: Site_ID replaced with fk_Practice_Site (surrogate key)
#   - Fact_Effective_Targets: new table + SP (pre-resolved site vs practice targets)
#   - Audit.Process_Config + Load_All: Fact_Effective_Targets step added
#
# Combines all SQL into a single sqlcmd batch (one auth prompt, one execution).

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "aihigginson@2rrjxy.onmicrosoft.com"
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

function Read-Fabric($file) {
    [System.IO.File]::ReadAllText((Join-Path $FabricDir $file), [System.Text.Encoding]::UTF8)
}

$sql = [System.Text.StringBuilder]::new()

$null = $sql.AppendLine("PRINT '=== 1. Table DDLs ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Gold.Dim_Date.Table.sql',
    'Gold.Fact_Daily_Targets.Table.sql',
    'Gold.Fact_Effective_Targets.Table.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine("PRINT '=== 2. Stored procedures ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Gold.usp_Load_Dim_Date.StoredProcedure.sql',
    'Gold.usp_Load_Dim_Date_Grouping.StoredProcedure.sql',
    'Gold.usp_Load_Fact_Targets.StoredProcedure.sql',
    'Gold.usp_Load_Fact_Daily_Targets.StoredProcedure.sql',
    'Gold.usp_Load_Fact_Effective_Targets.StoredProcedure.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine("PRINT '=== 3. Audit config ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Audit.Process_Config.Data.sql',
    'Audit.usp_Load_All.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine(@"
PRINT '=== 4. Fix Input.Targets period format ===';
GO
UPDATE Input.Targets
SET    Period_Value = 'FY ' + Period_Value
WHERE  Period_Type  = 'annual'
  AND  Period_Value NOT LIKE 'FY %';
PRINT CONCAT('Input.Targets rows updated: ', @@ROWCOUNT);
GO

PRINT '=== 5. Reload Gold SPs in dependency order ===';
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Date @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Dim_Date  I=', @i, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_Targets @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Fact_Targets  I=', @i, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_Daily_Targets @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Fact_Daily_Targets  I=', @i, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Fact_Effective_Targets @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Fact_Effective_Targets  I=', @i, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Date_Grouping @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Dim_Date_Grouping  I=', @i, '  D=', @d);
GO
PRINT 'All steps complete.';
GO
"@)

$tmpFile = Join-Path $env:TEMP "Deploy_Targets_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $sql.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Deploying targets update to $Database @ $Server" -ForegroundColor Cyan

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host ""
Write-Host "$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. In PBI Desktop, run TabularEditor_Revenue.csx to update the"
    Write-Host "     three daily-target measures (Total/NHS/Private Revenue Target)."
    Write-Host "  2. Refresh the PBI dataset."
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
    exit 1
}
