<#
.SYNOPSIS
    Deploy the {Entity}_Count column additions across all Gold Dim tables and load SPs,
    plus the cross-tenant fix to usp_Load_Fact_Treatment_Appointments.
.DESCRIPTION
    Runs tables first (DROP/CREATE adds the new TINYINT count column to each Dim),
    then recreates all 10 Dim load SPs, then the Treatment_Appointments fact SP.
    Does NOT run any data loads - run the SPs manually in Fabric after this deploys.
.PARAMETER Server
    Fabric SQL endpoint (defaults to dev workspace).
.PARAMETER Database
    Fabric Warehouse name (defaults to WH_Dentally).
.PARAMETER Username
    Azure AD email (defaults to admin@Analytically.info).
#>
param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "admin@Analytically.info"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$Groups = [ordered]@{

    '1. Gold Dim tables (DROP/CREATE adds count column)' = @(
        'Gold.Dim_Accounts.Table.sql'
        'Gold.Dim_Cancellation_Reasons.Table.sql'
        'Gold.Dim_Patients.Table.sql'
        'Gold.Dim_Payment_Plans.Table.sql'
        'Gold.Dim_Practice_Sites.Table.sql'
        'Gold.Dim_Practitioners.Table.sql'
        'Gold.Dim_Tenants.Table.sql'
        'Gold.Dim_Treatment_Plans.Table.sql'
        'Gold.Dim_Treatments.Table.sql'
        'Gold.Dim_Users.Table.sql'
    )

    '2. Gold Dim load SPs (populate count column)' = @(
        'Gold.usp_Load_Dim_Accounts.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Cancellation_Reasons.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Patients.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Payment_Plans.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Practice_Sites.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Practitioners.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Tenants.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Treatment_Plans.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Treatments.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Users.StoredProcedure.sql'
    )

    '3. Fact SP (cross-tenant Tenant_ID join fix)' = @(
        'Gold.usp_Load_Fact_Treatment_Appointments.StoredProcedure.sql'
    )
}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Deploying Dim count columns + Treatment_Appointments fix to $Database @ $Server" -ForegroundColor Cyan

$combined = [System.Text.StringBuilder]::new()
$count    = 0

foreach ($group in $Groups.GetEnumerator()) {
    $null = $combined.AppendLine("PRINT '>>> $($group.Key)';")
    $null = $combined.AppendLine("GO")
    foreach ($file in $group.Value) {
        $path = Join-Path $FabricDir $file
        if (-not (Test-Path $path)) {
            Write-Error "File not found: $path"
            exit 1
        }
        $null = $combined.AppendLine("PRINT '  FILE: $file';")
        $null = $combined.AppendLine("GO")
        $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        $null = $combined.AppendLine()
        $count++
    }
}

$tmpFile = Join-Path $env:TEMP "Deploy_DimCount_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Combined $count scripts."

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('=' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete. Next steps:" -ForegroundColor Green
    Write-Host "  1. Run Meta.usp_Create_Gold_Views in Fabric"
    Write-Host "  2. Run all 10 Gold.usp_Load_Dim_* SPs"
    Write-Host "  3. Run Gold.usp_Load_Fact_Treatment_Appointments"
    Write-Host "  4. Re-run TabularEditor_HomeDetail.csx and TabularEditor_Clinical.csx"
    Write-Host "  5. Refresh PBI semantic model"
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
