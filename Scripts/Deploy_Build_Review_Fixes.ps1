# Deploy_Build_Review_Fixes.ps1
# Deploys all build-review fixes:
#   - Gold.Fact_Invoice_Items: datetime -> datetime2(7) for DW metadata columns
#   - 5 Silver procedures: NULL bit type fixes, Practitioner_Diary datetimeoffset fix
#   - 16 Gold procedures: GETDATE() -> SYSUTCDATETIME(), CAST -> TRY_CAST hardening

$server  = "HST\HS2"
$db      = "Dentally"
$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

function Run-SQL($sql, $label) {
    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tmp, $sql, [System.Text.Encoding]::UTF8)
    Write-Host "Deploying: $label"
    sqlcmd -S $server -E -d $db -i $tmp -b
    if ($LASTEXITCODE -ne 0) { Write-Host "  ERROR in $label" -ForegroundColor Red }
    Remove-Item $tmp
}

function Deploy-Proc($file) {
    $path = Join-Path $FabricDir $file
    $sql  = (Get-Content $path -Raw) -replace '\bCREATE PROCEDURE\b', 'CREATE OR ALTER PROCEDURE'
    Run-SQL $sql $file
}

# 1. Schema change
Run-SQL @"
ALTER TABLE [Gold].[Fact_Invoice_Items] ALTER COLUMN [DW_Created_At] datetime2(7) NOT NULL;
ALTER TABLE [Gold].[Fact_Invoice_Items] ALTER COLUMN [DW_Updated_At] datetime2(7) NOT NULL;
"@ "Gold.Fact_Invoice_Items datetime2(7) columns"

# 2. Silver procedures
$silverProcs = @(
    "Silver.usp_Load_Patients.StoredProcedure.sql",
    "Silver.usp_Load_Sundries.StoredProcedure.sql",
    "Silver.usp_Load_Treatment_Categories.StoredProcedure.sql",
    "Silver.usp_Load_Treatments.StoredProcedure.sql",
    "Silver.usp_Load_Practitioner_Diary.StoredProcedure.sql"
)
foreach ($p in $silverProcs) { Deploy-Proc $p }

# 3. Gold procedures
$goldProcs = @(
    "Gold.usp_Load_Dim_Accounts.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Date.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Patients.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Payment_Plans.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Practice_Sites.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Practitioners.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Treatment_Plans.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Treatments.StoredProcedure.sql",
    "Gold.usp_Load_Dim_Users.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Appointments.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Contracts.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Invoice_Items.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Practitioner_Diaries.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Recalls.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Treatment_Appointments.StoredProcedure.sql",
    "Gold.usp_Load_Fact_Treatment_Plan_Items.StoredProcedure.sql"
)
foreach ($p in $goldProcs) { Deploy-Proc $p }

Write-Host "Done." -ForegroundColor Green
