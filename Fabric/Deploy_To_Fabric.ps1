<#
.SYNOPSIS
    Deploy all Dentally DW objects to a Microsoft Fabric Warehouse.
.DESCRIPTION
    Runs every Fabric/*.sql script in dependency order using sqlcmd.exe
    with Azure AD interactive authentication (same as SSMS).
.PARAMETER Server
    Fabric Warehouse SQL endpoint.
    Find it in Fabric portal: open your Warehouse → Settings → SQL connection string.
    Format: <workspace-id>.datawarehouse.fabric.microsoft.com
.PARAMETER Database
    Name of the Fabric Warehouse (the database name, not the workspace).
.PARAMETER Username
    Your Azure AD email address.
.EXAMPLE
   .\Deploy_To_Fabric.ps1 -Server  "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com" -Database "WH_Dentally"   -Username "aihigginson@2rrjxy.onmicrosoft.com"
#>
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Database,
    [Parameter(Mandatory)] [string] $Username
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found. It should be installed with SSMS at: C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\*\Tools\Binn\sqlcmd.exe"
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$Groups = [ordered]@{

    '1. Schemas' = @(
        'Audit.Schema.sql'
        'Stage.Schema.sql'
        'Bronze.Schema.sql'
        'Silver.Schema.sql'
        'Gold.Schema.sql'
        'Meta.Schema.sql'
        'PBI.Schema.sql'
        'dentally.Schema.sql'
        'Security.Schema.sql'
        'Input.Schema.sql'
        'Config.Schema.sql'
    )

    '2. Audit tables' = @(
        'Audit.Environment_Config.Table.sql'
        'Audit.Lakehouse_Map_Config.Table.sql'
        'Audit.Process_Category.Table.sql'
        'Audit.Process_Type.Table.sql'
        'Audit.Process_Config.Table.sql'
        'Audit.Process_Dependency.Table.sql'
        'Audit.Process_Execution_Log.Table.sql'
        'Audit.Process_Execution_Temp.Table.sql'
        'Audit.Process_Message_Log.Table.sql'
        'Audit.Record_Count_Log.Table.sql'
        'Audit.Meta_Table_Profile.Table.sql'
        'Audit.Meta_Column_Profile.Table.sql'
        'Audit.Tenants.Table.sql'
    )

    '2b. Security tables' = @(
        'Security.Clients.Table.sql'
        'Security.Application_Users.Table.sql'
        'Security.User_Tenants.Table.sql'
    )

    '2c. Input tables' = @(
        'Input.Targets.Table.sql'
    )

    '2d. Config tables' = @(
        'Config.Metric_Definitions.Table.sql'
        'Config.Metric_Period_Types.Table.sql'
    )

    '3. Audit seed data' = @(
        'Config.Metric_Definitions.Data.sql'
        'Config.Metric_Period_Types.Data.sql'
        'Audit.Process_Category.Data.sql'
        'Audit.Process_Type.Data.sql'
        'Audit.Process_Config.Data.sql'
        'Audit.Tenants.Data.sql'
        'Security.Clients.Data.sql'
        'Security.Application_Users.Data.sql'
        'Security.User_Tenants.Data.sql'
    )

    '3b. Input data cleanup' = @(
        'Input.Targets.Cleanup.sql'
    )

    '4. Audit functions & procedures' = @(
        'Audit.ETL_Error_Handler.UserDefinedFunction.sql'
        'Audit.ETL_Start_Run.StoredProcedure.sql'
        'Audit.ETL_Finish_Run.StoredProcedure.sql'
        'Audit.ETL_Log_Message.StoredProcedure.sql'
        'Audit.ETL_Run_Process.StoredProcedure.sql'
        'Audit.ETL_Execution_Log_Cleanup.StoredProcedure.sql'
        'Audit.Meta_Log_Record_Count.StoredProcedure.sql'
        'Audit.Meta_Refresh_Record_Count.StoredProcedure.sql'
    )

    '5. Audit views' = @(
        'Audit.v_24Hr_Processes.View.sql'
        'Audit.v_48Hr_Processes.View.sql'
        'Audit.v_Custom_Messages.View.sql'
        'Audit.v_Daily_Messages.View.sql'
        'Audit.v_Daily_Processes.View.sql'
        'Audit.v_Debug_Messages.View.sql'
        'Audit.v_Error_Messages.View.sql'
        'Audit.v_Info_Messages.View.sql'
        'Audit.v_Process_Dependencies.View.sql'
        'Audit.v_Warn_Messages.View.sql'
    )

    '6. dbo functions' = @(
        'dbo.CapitaliseSnakeCase.UserDefinedFunction.sql'
    )

    '7. Bronze tables' = @(
        'Bronze.Accounts.Table.sql'
        'Bronze.Acquisition_Sources.Table.sql'
        'Bronze.Appointments.Table.sql'
        'Bronze.Bank_Holidays.Table.sql'
        'Bronze.Contracts.Table.sql'
        'Bronze.Ethnicity_Codes.Table.sql'
        'Bronze.Fees.Table.sql'
        'Bronze.Invoice_Items.Table.sql'
        'Bronze.Invoices.Table.sql'
        'Bronze.NHS_Claims.Table.sql'
        'Bronze.NHS_Codes.Table.sql'
        'Bronze.Patient_Stats.Table.sql'
        'Bronze.Patients.Table.sql'
        'Bronze.Payment_Allocations.Table.sql'
        'Bronze.Payment_Explanations.Table.sql'
        'Bronze.Payment_Plans.Table.sql'
        'Bronze.Payments.Table.sql'
        'Bronze.Practice.Table.sql'
        'Bronze.Practitioner_Diary.Table.sql'
        'Bronze.Practitioner_Diary_Breaks.Table.sql'
        'Bronze.Practitioners.Table.sql'
        'Bronze.Recalls.Table.sql'
        'Bronze.Sites.Table.sql'
        'Bronze.Sundries.Table.sql'
        'Bronze.Treatment_Appointments.Table.sql'
        'Bronze.Treatment_Categories.Table.sql'
        'Bronze.Treatment_Plan_Items.Table.sql'
        'Bronze.Treatment_Plans.Table.sql'
        'Bronze.Treatments.Table.sql'
        'Bronze.Users.Table.sql'
        'Bronze.Waiting_Lists.Table.sql'
    )

    '8. Stage views' = @(
        'Stage.Views.sql'
    )

    '9. Bronze procedures' = @(
        'Bronze.usp_Load_Practice.StoredProcedure.sql'
        'Bronze.usp_Load_Sites.StoredProcedure.sql'
        'Bronze.usp_Load_Users.StoredProcedure.sql'
        'Bronze.usp_Load_Practitioners.StoredProcedure.sql'
        'Bronze.usp_Load_Payment_Plans.StoredProcedure.sql'
        'Bronze.usp_Load_Treatments.StoredProcedure.sql'
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
        'Bronze.usp_Load_Treatment_Categories.StoredProcedure.sql'
        'Bronze.usp_Load_Acquisition_Sources.StoredProcedure.sql'
        'Bronze.usp_Load_Sundries.StoredProcedure.sql'
        'Bronze.usp_Load_Contracts.StoredProcedure.sql'
        'Bronze.usp_Load_Fees.StoredProcedure.sql'
        'Bronze.usp_Load_Practitioner_Diary_Breaks.StoredProcedure.sql'
        'Bronze.usp_Load_NHS_Claims.StoredProcedure.sql'
        'Bronze.usp_Load_Patient_Stats.StoredProcedure.sql'
        'Bronze.usp_Load_Payment_Allocations.StoredProcedure.sql'
        'Bronze.usp_Load_Payment_Explanations.StoredProcedure.sql'
        'Bronze.usp_Load_Treatment_Appointments.StoredProcedure.sql'
        'Bronze.usp_Load_All.StoredProcedure.sql'
    )

    '10. Silver tables' = @(
        'Silver.Accounts.Table.sql'
        'Silver.Acquisition_Sources.Table.sql'
        'Silver.Appointment_Cancellation_Reasons.Table.sql'
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
    )

    '12. Silver procedures' = @(
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
    )

    '15. Meta procedures' = @(
        'Meta.usp_Create_Gold_Views.StoredProcedure.sql'
    )

}

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

Write-Host "Deploying Dentally DW to $Database @ $Server" -ForegroundColor Cyan
Write-Host "Building combined script..."

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

$tmpFile = Join-Path $env:TEMP "Deploy_Dentally_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Combined $count scripts into: $tmpFile"
Write-Host "A browser login window will open for Azure AD authentication.`n"

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete: all $count scripts deployed successfully." -ForegroundColor Green
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
