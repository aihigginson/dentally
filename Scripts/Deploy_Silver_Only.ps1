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

$Groups = [ordered]@{

    '09. Silver tables' = @(
        'Silver.Accounts.Table.sql'
        'Silver.Acquisition_Sources.Table.sql'
        'Silver.Appointment_Cancellation_Reasons.Table.sql'
        'Silver.Appointment_Journey_Attributes.Table.sql'
        'Silver.Appointments.Table.sql'
        'Silver.Contracts.Table.sql'
        'Silver.Fees.Table.sql'
        'Silver.Invoice_Items.Table.sql'
        'Silver.Invoices.Table.sql'
        'Silver.NHS_Claims.Table.sql'
        'Silver.Patient_Referral_Reasons.Table.sql'
        'Silver.Patient_Referrals.Table.sql'
        'Silver.Patient_Stats.Table.sql'
        'Silver.Patients.Table.sql'
        'Silver.Payment_Allocations.Table.sql'
        'Silver.Payment_Explanations.Table.sql'
        'Silver.Payment_Plans.Table.sql'
        'Silver.Payments.Table.sql'
        'Silver.Practice.Table.sql'
        'Silver.Practitioner_Diary.Table.sql'
        'Silver.Practitioner_Diary_Breaks.Table.sql'
        'Silver.Practitioners.Table.sql'
        'Silver.Recalls.Table.sql'
        'Silver.Rooms.Table.sql'
        'Silver.Sites.Table.sql'
        'Silver.Sundries.Table.sql'
        'Silver.Treatment_Appointments.Table.sql'
        'Silver.Treatment_Categories.Table.sql'
        'Silver.Treatment_Plan_Items.Table.sql'
        'Silver.Treatment_Plans.Table.sql'
        'Silver.Treatments.Table.sql'
        'Silver.Users.Table.sql'
        'Silver.Waiting_List_Entries.Table.sql'
    )

    '10. Silver stored procedures' = @(
        'Silver.usp_Load_Accounts.StoredProcedure.sql'
        'Silver.usp_Load_Acquisition_Sources.StoredProcedure.sql'
        'Silver.usp_Load_Appointments.StoredProcedure.sql'
        'Silver.usp_Load_Contracts.StoredProcedure.sql'
        'Silver.usp_Load_Fees.StoredProcedure.sql'
        'Silver.usp_Load_Invoice_Items.StoredProcedure.sql'
        'Silver.usp_Load_Invoices.StoredProcedure.sql'
        'Silver.usp_Load_NHS_Claims.StoredProcedure.sql'
        'Silver.usp_Load_Patient_Stats.StoredProcedure.sql'
        'Silver.usp_Load_Patients.StoredProcedure.sql'
        'Silver.usp_Load_Payment_Allocations.StoredProcedure.sql'
        'Silver.usp_Load_Payment_Explanations.StoredProcedure.sql'
        'Silver.usp_Load_Payment_Plans.StoredProcedure.sql'
        'Silver.usp_Load_Payments.StoredProcedure.sql'
        'Silver.usp_Load_Practice.StoredProcedure.sql'
        'Silver.usp_Load_Practitioner_Diary.StoredProcedure.sql'
        'Silver.usp_Load_Practitioner_Diary_Breaks.StoredProcedure.sql'
        'Silver.usp_Load_Practitioners.StoredProcedure.sql'
        'Silver.usp_Load_Recalls.StoredProcedure.sql'
        'Silver.usp_Load_Sites.StoredProcedure.sql'
        'Silver.usp_Load_Sundries.StoredProcedure.sql'
        'Silver.usp_Load_Treatment_Appointments.StoredProcedure.sql'
        'Silver.usp_Load_Treatment_Categories.StoredProcedure.sql'
        'Silver.usp_Load_Treatment_Plan_Items.StoredProcedure.sql'
        'Silver.usp_Load_Treatment_Plans.StoredProcedure.sql'
        'Silver.usp_Load_Treatments.StoredProcedure.sql'
        'Silver.usp_Load_Users.StoredProcedure.sql'
        'Silver.usp_Load_Appointment_Journey_Attributes.StoredProcedure.sql'
    )
}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Deploying Silver layer to $Database @ $Server" -ForegroundColor Cyan

$combined = [System.Text.StringBuilder]::new()
$count = 0

foreach ($group in $Groups.GetEnumerator()) {
    $null = $combined.AppendLine("PRINT '>>> GROUP: $($group.Key)';")
    $null = $combined.AppendLine("GO")
    foreach ($file in $group.Value) {
        $path = Join-Path $FabricDir $file
        $null = $combined.AppendLine("PRINT '  FILE: $file';")
        $null = $combined.AppendLine("GO")
        $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        $null = $combined.AppendLine()
        $count++
    }
}

$tmpFile = Join-Path $env:TEMP "Deploy_Silver_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Combined $count scripts into: $tmpFile"

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete: Silver layer deployed successfully." -ForegroundColor Green
    Write-Host "Note: Silver tables were dropped and recreated -- run Silver load SPs to repopulate." -ForegroundColor Yellow
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
