param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [Parameter(Mandatory)] [string] $Username
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$Groups = [ordered]@{

    '11. Gold tables & functions' = @(
        'Gold.Dim_Accounts.Table.sql'
        'Gold.Dim_Date.Table.sql'
        'Gold.Dim_Patients.Table.sql'
        'Gold.Dim_Payment_Plans.Table.sql'
        'Gold.Dim_Practice_Sites.Table.sql'
        'Gold.Dim_Practitioners.Table.sql'
        'Gold.Dim_Treatment_Plans.Table.sql'
        'Gold.Dim_Treatments.Table.sql'
        'Gold.Dim_Users.Table.sql'
        'Gold.Fact_Appointments.Table.sql'
        'Gold.Fact_Contracts.Table.sql'
        'Gold.Fact_Invoice_Items.Table.sql'
        'Gold.Fact_Practitioner_Diaries.Table.sql'
        'Gold.Fact_Recalls.Table.sql'
        'Gold.Fact_Treatment_Appointments.Table.sql'
        'Gold.Fact_Treatment_Plan_Items.Table.sql'
        'Gold.Fact_Targets.Table.sql'
        'Gold.fn_Get_Date_Key.UserDefinedFunction.sql'
        'Gold.Dim_Tenants.Table.sql'
        'Gold.Aggregate_Site_Patient_Practitioner_Daily.Table.sql'
        'Gold.Aggregate_Site_Patient_Current.Table.sql'
        'Gold.Aggregate_Site_Practitioner_Current.Table.sql'
    )

    '13. Gold usp_Create procedures' = @(
        'Gold.usp_Create_Dim_Accounts.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Patients.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Payment_Plans.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Practice_Sites.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Practitioners.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Treatment_Plans.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Treatments.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Users.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Appointments.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Contracts.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Invoice_Items.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Practitioner_Diaries.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Recalls.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Treatment_Appointments.StoredProcedure.sql'
        'Gold.usp_Create_Fact_Treatment_Plan_Items.StoredProcedure.sql'
        'Gold.usp_Create_Dim_Tenants.StoredProcedure.sql'
    )

    '14. Gold usp_Load procedures' = @(
        'Gold.usp_Load_Dim_Accounts.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Date.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Date_Grouping.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Patients.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Payment_Plans.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Practice_Sites.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Practitioners.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Treatment_Plans.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Treatments.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Users.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Appointments.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Contracts.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Invoice_Items.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Practitioner_Diaries.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Recalls.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Treatment_Appointments.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Treatment_Plan_Items.StoredProcedure.sql'
        'Gold.usp_Load_Dim_Tenants.StoredProcedure.sql'
        'Gold.usp_Load_Fact_Targets.StoredProcedure.sql'
        'Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily.StoredProcedure.sql'
        'Gold.usp_Load_Aggregate_Site_Patient_Current.StoredProcedure.sql'
        'Gold.usp_Load_Aggregate_Site_Practitioner_Current.StoredProcedure.sql'
    )
}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Deploying Gold layer to $Database @ $Server" -ForegroundColor Cyan

$combined = [System.Text.StringBuilder]::new()
$count = 0

foreach ($group in $Groups.GetEnumerator()) {
    $null = $combined.AppendLine("PRINT '>>> GROUP: $($group.Key)';")
    $null = $combined.AppendLine("GO")
    foreach ($file in $group.Value) {
        $path = Join-Path $ScriptDir $file
        $null = $combined.AppendLine("PRINT '  FILE: $file';")
        $null = $combined.AppendLine("GO")
        $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        $null = $combined.AppendLine()
        $count++
    }
}

$tmpFile = Join-Path $env:TEMP "Deploy_Gold_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Combined $count scripts into: $tmpFile"

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete: Gold layer deployed successfully." -ForegroundColor Green
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
