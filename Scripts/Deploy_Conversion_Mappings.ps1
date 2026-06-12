# Deploy_Conversion_Mappings.ps1
# Deploys the conversion mapping architecture:
#   1. Config.*_Standard tables (DROP/CREATE) + seed data
#   2. Input.*_Map tables (create if not exists)
#   3. Gold Dim table DDLs (DROP/CREATE - data repopulated in step 5)
#   4. Gold load SPs (DROP/CREATE)
#   5. Run load SPs to repopulate Gold Dims with Standard_* columns
#
# After running this script, load mapping templates via:
#   py Scripts/Generate_Mapping_Template.py --server <endpoint> --database WH_Dentally --tenant <id> --entity <entity> --auth interactive
#   py Scripts/Load_Mapping_From_Template.py --server <endpoint> --database WH_Dentally --input Mappings/T<id>_<entity>.xlsx --auth interactive
# Then re-run the relevant Gold load SPs (or Load_All) to resolve Standard_* values.

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

function Read-Fabric($file) {
    [System.IO.File]::ReadAllText((Join-Path $FabricDir $file), [System.Text.Encoding]::UTF8)
}

$sql = [System.Text.StringBuilder]::new()

$null = $sql.AppendLine("PRINT '=== 1. Config standard tables ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Config.Treatment_Category_Standard.Table.sql',
    'Config.Acquisition_Source_Standard.Table.sql',
    'Config.Cancellation_Reason_Standard.Table.sql',
    'Config.Payment_Plan_Standard.Table.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine("PRINT '=== 2. Config seed data ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Config.Treatment_Category_Standard.Data.sql',
    'Config.Acquisition_Source_Standard.Data.sql',
    'Config.Cancellation_Reason_Standard.Data.sql',
    'Config.Payment_Plan_Standard.Data.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine("PRINT '=== 3. Input mapping tables ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Input.Treatment_Category_Map.Table.sql',
    'Input.Acquisition_Source_Map.Table.sql',
    'Input.Cancellation_Reason_Map.Table.sql',
    'Input.Payment_Plan_Map.Table.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine("PRINT '=== 4. Gold Dim table DDLs (DROP/CREATE) ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Gold.Dim_Treatments.Table.sql',
    'Gold.Dim_Acquisition_Sources.Table.sql',
    'Gold.Dim_Cancellation_Reasons.Table.sql',
    'Gold.Dim_Payment_Plans.Table.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine("PRINT '=== 5. Gold load stored procedures ===';")
$null = $sql.AppendLine("GO")
foreach ($f in @(
    'Gold.usp_Load_Dim_Treatments.StoredProcedure.sql',
    'Gold.usp_Load_Dim_Acquisition_Sources.StoredProcedure.sql',
    'Gold.usp_Load_Dim_Cancellation_Reasons.StoredProcedure.sql',
    'Gold.usp_Load_Dim_Payment_Plans.StoredProcedure.sql'
)) {
    $null = $sql.AppendLine("PRINT '  $f';")
    $null = $sql.AppendLine("GO")
    $null = $sql.AppendLine((Read-Fabric $f))
}

$null = $sql.AppendLine(@"
PRINT '=== 6. Repopulate Gold Dims ===';
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Treatments @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Dim_Treatments  I=', @i, '  U=', @u, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Acquisition_Sources @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Dim_Acquisition_Sources  I=', @i, '  U=', @u, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Cancellation_Reasons @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Dim_Cancellation_Reasons  I=', @i, '  U=', @u, '  D=', @d);
GO
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC Gold.usp_Load_Dim_Payment_Plans @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
PRINT CONCAT('usp_Load_Dim_Payment_Plans  I=', @i, '  U=', @u, '  D=', @d);
GO
PRINT 'All steps complete.';
GO
"@)

$tmpFile = Join-Path $env:TEMP "Deploy_Conversion_Mappings_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $sql.ToString(), [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Deploying conversion mapping architecture to $Database @ $Server" -ForegroundColor Cyan

& sqlcmd -S $Server -d $Database -G -U $Username -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host ""
Write-Host "$('=' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Tune Config.*_Standard seed values if needed and re-run this script."
    Write-Host "  2. For each tenant + entity, generate and fill a mapping template:"
    Write-Host "       py Scripts/Generate_Mapping_Template.py --server $Server --database $Database --tenant <id> --entity <entity> --auth interactive"
    Write-Host "  3. Load completed templates:"
    Write-Host "       py Scripts/Load_Mapping_From_Template.py --server $Server --database $Database --input Mappings/T<id>_<entity>.xlsx --auth interactive"
    Write-Host "  4. Re-run the Gold load SPs (or Load_All) to resolve Standard_* values."
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
    exit 1
}
