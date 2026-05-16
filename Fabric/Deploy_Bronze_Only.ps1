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

    '05. Stage views' = @(
        'Stage.Views.sql'
    )

    '06. Bronze tables' = @(
        'Bronze.Invoice_Items.Table.sql'
        'Bronze.Practitioners.Table.sql'
        'Bronze.Recalls.Table.sql'
        'Bronze.Waiting_Lists.Table.sql'
        'Bronze.Cancellation_Reasons.Table.sql'
    )

    '07. Bronze stored procedures' = @(
        'Bronze.usp_Load_Practice.StoredProcedure.sql'
        'Bronze.usp_Load_Sites.StoredProcedure.sql'
        'Bronze.usp_Load_Users.StoredProcedure.sql'
        'Bronze.usp_Load_Practitioners.StoredProcedure.sql'
        'Bronze.usp_Load_Payment_Plans.StoredProcedure.sql'
        'Bronze.usp_Load_Treatments.StoredProcedure.sql'
        'Bronze.usp_Load_Treatment_Categories.StoredProcedure.sql'
        'Bronze.usp_Load_Acquisition_Sources.StoredProcedure.sql'
        'Bronze.usp_Load_Cancellation_Reasons.StoredProcedure.sql'
        'Bronze.usp_Load_Waiting_Lists.StoredProcedure.sql'
        'Bronze.usp_Load_Sundries.StoredProcedure.sql'
        'Bronze.usp_Load_Contracts.StoredProcedure.sql'
        'Bronze.usp_Load_Fees.StoredProcedure.sql'
        'Bronze.usp_Load_Practitioner_Diary_Breaks.StoredProcedure.sql'
        'Bronze.usp_Load_Patients.StoredProcedure.sql'
        'Bronze.usp_Load_Accounts.StoredProcedure.sql'
        'Bronze.usp_Load_Appointments.StoredProcedure.sql'
        'Bronze.usp_Load_Invoices.StoredProcedure.sql'
        'Bronze.usp_Load_Invoice_Items.StoredProcedure.sql'
        'Bronze.usp_Load_Payments.StoredProcedure.sql'
        'Bronze.usp_Load_Treatment_Plans.StoredProcedure.sql'
        'Bronze.usp_Load_Treatment_Plan_Items.StoredProcedure.sql'
        'Bronze.usp_Load_Recalls.StoredProcedure.sql'
        'Bronze.usp_Load_Practitioner_Diary_Entries.StoredProcedure.sql'
        'Bronze.usp_Load_NHS_Claims.StoredProcedure.sql'
        'Bronze.usp_Load_Patient_Stats.StoredProcedure.sql'
        'Bronze.usp_Load_Payment_Allocations.StoredProcedure.sql'
        'Bronze.usp_Load_Payment_Explanations.StoredProcedure.sql'
        'Bronze.usp_Load_Treatment_Appointments.StoredProcedure.sql'
        'Bronze.usp_Load_Patient_Referrals.StoredProcedure.sql'
        'Bronze.usp_Load_All.StoredProcedure.sql'
    )
}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Deploying Bronze layer to $Database @ $Server" -ForegroundColor Cyan

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

$tmpFile = Join-Path $env:TEMP "Deploy_Bronze_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Combined $count scripts into: $tmpFile"

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete: Bronze layer deployed successfully." -ForegroundColor Green
    Write-Host "Next: run the Fabric pipeline (Stage_Ingest -> Bronze.usp_Load_All) to repopulate Bronze." -ForegroundColor Yellow
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
