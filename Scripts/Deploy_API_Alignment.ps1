# Deploy_API_Alignment.ps1
# Full Bronze + Silver schema alignment to real Dentally API shape.
# Covers all column renames, type corrections, new fields, and one new entity (Rooms).
# After deploy: run the Fabric Bronze pipeline (Stage -> Bronze.usp_Load_All) then re-run Silver SPs.

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

$Errors = 0

function Deploy-Group($label, $files) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    $combined = [System.Text.StringBuilder]::new()
    foreach ($f in $files) {
        $path = Join-Path $FabricDir $f
        if (-not (Test-Path $path)) {
            Write-Host "  MISSING: $f" -ForegroundColor Red
            $script:Errors++
            continue
        }
        $null = $combined.AppendLine("PRINT '  $f';")
        $null = $combined.AppendLine("GO")
        $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
        $null = $combined.AppendLine()
    }
    $tmp = Join-Path $env:TEMP "deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff').sql"
    [System.IO.File]::WriteAllText($tmp, $combined.ToString(), [System.Text.Encoding]::UTF8)
    & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i $tmp -b
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED" -ForegroundColor Red
        $script:Errors++
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
    Remove-Item $tmp -Force
}

function Run-SQL($sql, $label) {
    Write-Host "  $label" -NoNewline
    $tmp = Join-Path $env:TEMP "run_$(Get-Date -Format 'yyyyMMdd_HHmmss_fff').sql"
    [System.IO.File]::WriteAllText($tmp, $sql, [System.Text.Encoding]::UTF8)
    & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i $tmp -b | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR" -ForegroundColor Red
        $script:Errors++
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
    Remove-Item $tmp -Force
}

# ---------------------------------------------------------------------------
# PHASE 0 -Stage views (TRY/CATCH: safe to run before Stage_Ingest)
# ---------------------------------------------------------------------------

Deploy-Group "0. Stage views" @(
    'Stage.Views.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Stage view errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 1 -Bronze tables (DROP/CREATE: all Bronze data will be lost)
# Repopulate by running the Fabric pipeline after deploy.
# ---------------------------------------------------------------------------

Deploy-Group "1. Bronze tables -modified" @(
    'Bronze.Appointments.Table.sql'             # removed site_id, created_at, updated_at
    'Bronze.Contracts.Table.sql'                # added Name, Notes
    'Bronze.Invoices.Table.sql'                 # added Sent_At
    'Bronze.NHS_Claims.Table.sql'               # added 5 financial fields
    'Bronze.Payments.Table.sql'                 # Reference/Transaction_Number VARCHAR (was DECIMAL)
    'Bronze.Treatment_Appointments.Table.sql'   # added Completed, Completed_At
    'Bronze.Patients.Table.sql'                 # added Emergency_Contact_*, Archived_Reason
    'Bronze.Treatments.Table.sql'               # ID->int, added Active, Code/NHS_Treatment_Cat VARCHAR
    'Bronze.Treatment_Plan_Items.Table.sql'     # added Surfaces, Teeth
    'Bronze.Cancellation_Reasons.Table.sql'     # Reason (was Name), Reason_Type, timestamps
    'Bronze.Practitioner_Diary_Breaks.Table.sql'# added ID, Name (was Break_Name)
    'Bronze.Sites.Table.sql'                    # Nickname VARCHAR (was DECIMAL), added Email_Address
    'Bronze.Practice.Table.sql'                 # Phone_Number VARCHAR (was DECIMAL)
    'Bronze.Recalls.Table.sql'                  # added First_Reminder_ID, Second_Reminder_ID
    'Bronze.Practitioners.Table.sql'            # Practitioner_Gdc_Number -> Practitioner_GDC_Number
    'Bronze.Patient_Stats.Table.sql'            # Last_Fta -> Last_FTA, NHS -> NHS, Patient_Id -> Patient_ID
    'Bronze.Invoice_Items.Table.sql'            # Invoice_Id, Treatment_Plan_Item_Id -> _ID
    'Bronze.Treatment_Plans.Table.sql'          # Patient_Id, Site_Id -> _ID
    'Bronze.Accounts.Table.sql'                 # Patient_Id -> Patient_ID
    'Bronze.Payment_Plans.Table.sql'            # Payment_Plan_Site_Id -> _ID
    'Bronze.Payment_Allocations.Table.sql'      # Payment_Id, Invoice_Id -> _ID
    'Bronze.Payment_Explanations.Table.sql'     # Payment_Id -> _ID
    'Bronze.Fees.Table.sql'                     # Fee_Id, Payment_Plan_Id -> _ID
    'Bronze.Users.Table.sql'                    # User_Id, Site_Id -> _ID
    'Bronze.Sundries.Table.sql'                 # Sundry_Id -> _ID
    'Bronze.Waiting_Lists.Table.sql'            # Patient_Id -> _ID
    'Bronze.Patient_Referrals.Table.sql'        # Patient_Id -> _ID
    'Bronze.Practitioner_Diary.Table.sql'       # Practitioner_Id -> _ID
)

if ($Errors -gt 0) { Write-Host "`nAborting after Bronze table errors." -ForegroundColor Red; exit 1 }

Deploy-Group "2. Bronze tables -new entities" @(
    'Bronze.Rooms.Table.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after new Bronze table errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 2 -Bronze stored procedures
# ---------------------------------------------------------------------------

Deploy-Group "3. Bronze stored procedures -all (tables rebuilt in Phase 1, all SPs must match)" @(
    'Bronze.usp_Load_Accounts.StoredProcedure.sql'
    'Bronze.usp_Load_Acquisition_Sources.StoredProcedure.sql'
    'Bronze.usp_Load_Appointments.StoredProcedure.sql'
    'Bronze.usp_Load_Cancellation_Reasons.StoredProcedure.sql'
    'Bronze.usp_Load_Contracts.StoredProcedure.sql'
    'Bronze.usp_Load_Fees.StoredProcedure.sql'
    'Bronze.usp_Load_Invoice_Items.StoredProcedure.sql'
    'Bronze.usp_Load_Invoices.StoredProcedure.sql'
    'Bronze.usp_Load_NHS_Claims.StoredProcedure.sql'
    'Bronze.usp_Load_Patient_Referral_Reasons.StoredProcedure.sql'
    'Bronze.usp_Load_Patient_Referrals.StoredProcedure.sql'
    'Bronze.usp_Load_Patient_Stats.StoredProcedure.sql'
    'Bronze.usp_Load_Patients.StoredProcedure.sql'
    'Bronze.usp_Load_Payment_Allocations.StoredProcedure.sql'
    'Bronze.usp_Load_Payment_Explanations.StoredProcedure.sql'
    'Bronze.usp_Load_Payment_Plans.StoredProcedure.sql'
    'Bronze.usp_Load_Payments.StoredProcedure.sql'
    'Bronze.usp_Load_Practice.StoredProcedure.sql'
    'Bronze.usp_Load_Practitioner_Diary_Breaks.StoredProcedure.sql'
    'Bronze.usp_Load_Practitioner_Diary_Entries.StoredProcedure.sql'
    'Bronze.usp_Load_Practitioners.StoredProcedure.sql'
    'Bronze.usp_Load_Recalls.StoredProcedure.sql'
    'Bronze.usp_Load_Sites.StoredProcedure.sql'
    'Bronze.usp_Load_Sundries.StoredProcedure.sql'
    'Bronze.usp_Load_Treatment_Appointments.StoredProcedure.sql'
    'Bronze.usp_Load_Treatment_Categories.StoredProcedure.sql'
    'Bronze.usp_Load_Treatment_Plan_Items.StoredProcedure.sql'
    'Bronze.usp_Load_Treatment_Plans.StoredProcedure.sql'
    'Bronze.usp_Load_Treatments.StoredProcedure.sql'
    'Bronze.usp_Load_Users.StoredProcedure.sql'
    'Bronze.usp_Load_Waiting_Lists.StoredProcedure.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Bronze SP errors." -ForegroundColor Red; exit 1 }

Deploy-Group "4. Bronze stored procedures -new entities + Load_All" @(
    'Bronze.usp_Load_Rooms.StoredProcedure.sql'
    'Bronze.usp_Load_All.StoredProcedure.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after new Bronze SP errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 3 -Silver tables (DROP/CREATE: Silver data lost, will reload from Bronze)
# ---------------------------------------------------------------------------

Deploy-Group "5. Silver tables -full rebuild (column naming fixes + schema changes)" @(
    'Silver.Patients.Table.sql'
    'Silver.Rooms.Table.sql'
    'Silver.Treatment_Appointments.Table.sql'
    'Silver.Recalls.Table.sql'
    'Silver.Sites.Table.sql'
    'Silver.Appointments.Table.sql'
    'Silver.Contracts.Table.sql'
    'Silver.Practice.Table.sql'
    'Silver.Treatments.Table.sql'
    'Silver.Treatment_Plans.Table.sql'
    'Silver.Treatment_Plan_Items.Table.sql'
    'Silver.Invoices.Table.sql'
    'Silver.Invoice_Items.Table.sql'
    'Silver.NHS_Claims.Table.sql'
    'Silver.Payments.Table.sql'
    'Silver.Payment_Plans.Table.sql'
    'Silver.Payment_Allocations.Table.sql'
    'Silver.Payment_Explanations.Table.sql'
    'Silver.Accounts.Table.sql'
    'Silver.Practitioners.Table.sql'
    'Silver.Practitioner_Diary.Table.sql'
    'Silver.Practitioner_Diary_Breaks.Table.sql'
    'Silver.Patient_Stats.Table.sql'
    'Silver.Patient_Referrals.Table.sql'
    'Silver.Patient_Referral_Reasons.Table.sql'
    'Silver.Acquisition_Sources.Table.sql'
    'Silver.Appointment_Cancellation_Reasons.Table.sql'
    'Silver.Appointment_Reason_Map.Table.sql'
    'Silver.Appointment_Journey_Attributes.Table.sql'
    'Silver.Sundries.Table.sql'
    'Silver.Waiting_List_Entries.Table.sql'
    'Silver.Fees.Table.sql'
    'Silver.Users.Table.sql'
    'Silver.Treatment_Categories.Table.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Silver table errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 4 -Silver stored procedures
# ---------------------------------------------------------------------------

Deploy-Group "6. Silver stored procedures -all (column naming fixes + schema changes)" @(
    'Silver.usp_Load_Appointments.StoredProcedure.sql'
    'Silver.usp_Load_Contracts.StoredProcedure.sql'
    'Silver.usp_Load_Invoices.StoredProcedure.sql'
    'Silver.usp_Load_Invoice_Items.StoredProcedure.sql'
    'Silver.usp_Load_NHS_Claims.StoredProcedure.sql'
    'Silver.usp_Load_Patients.StoredProcedure.sql'
    'Silver.usp_Load_Sites.StoredProcedure.sql'
    'Silver.usp_Load_Practice.StoredProcedure.sql'
    'Silver.usp_Load_Treatments.StoredProcedure.sql'
    'Silver.usp_Load_Treatment_Plans.StoredProcedure.sql'
    'Silver.usp_Load_Treatment_Plan_Items.StoredProcedure.sql'
    'Silver.usp_Load_Treatment_Appointments.StoredProcedure.sql'
    'Silver.usp_Load_Recalls.StoredProcedure.sql'
    'Silver.usp_Load_Practitioner_Diary_Breaks.StoredProcedure.sql'
    'Silver.usp_Load_Practitioner_Diary.StoredProcedure.sql'
    'Silver.usp_Load_Practitioners.StoredProcedure.sql'
    'Silver.usp_Load_Payments.StoredProcedure.sql'
    'Silver.usp_Load_Payment_Plans.StoredProcedure.sql'
    'Silver.usp_Load_Payment_Allocations.StoredProcedure.sql'
    'Silver.usp_Load_Payment_Explanations.StoredProcedure.sql'
    'Silver.usp_Load_Accounts.StoredProcedure.sql'
    'Silver.usp_Load_Acquisition_Sources.StoredProcedure.sql'
    'Silver.usp_Load_Patient_Stats.StoredProcedure.sql'
    'Silver.usp_Load_Patient_Referrals.StoredProcedure.sql'
    'Silver.usp_Load_Patient_Referral_Reasons.StoredProcedure.sql'
    'Silver.usp_Load_Sundries.StoredProcedure.sql'
    'Silver.usp_Load_Fees.StoredProcedure.sql'
    'Silver.usp_Load_Users.StoredProcedure.sql'
    'Silver.usp_Load_Treatment_Categories.StoredProcedure.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Silver SP errors." -ForegroundColor Red; exit 1 }

Deploy-Group "7. Silver stored procedures -new entities + derive" @(
    'Silver.usp_Load_Rooms.StoredProcedure.sql'
    'Silver.usp_Load_Appointment_Cancellation_Reasons.StoredProcedure.sql'
    'Silver.usp_Load_Appointment_Journey_Attributes.StoredProcedure.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Silver SP errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 5 - Add Process_Config rows for new entity (Rooms)
# 8 tenants x 1 entity = 8 new rows
# ---------------------------------------------------------------------------

Deploy-Group "8. Process_Config - new entity rows" @(
    'Audit.Process_Config.New_Entities.Data.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Process_Config errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 6 - Gold tables (DROP/CREATE: Gold data will be lost, reload via Gold SPs after deploy)
# ---------------------------------------------------------------------------

Deploy-Group "9. Gold tables -full rebuild (column naming fixes)" @(
    'Gold.Dim_Practice_Sites.Table.sql'
    'Gold.Dim_Patients.Table.sql'
    'Gold.Dim_Practitioners.Table.sql'
    'Gold.Dim_Accounts.Table.sql'
    'Gold.Dim_Users.Table.sql'
    'Gold.Dim_Payment_Plans.Table.sql'
    'Gold.Dim_Treatment_Plans.Table.sql'
    'Gold.Dim_Treatments.Table.sql'
    'Gold.Dim_Tenants.Table.sql'
    'Gold.Dim_Date.Table.sql'
    'Gold.Fact_Recalls.Table.sql'
    'Gold.Fact_Invoice_Items.Table.sql'
    'Gold.Fact_Treatment_Appointments.Table.sql'
    'Gold.Fact_Treatment_Plan_Items.Table.sql'
    'Gold.Fact_Appointments.Table.sql'
    'Gold.Fact_Contracts.Table.sql'
    'Gold.Fact_Practitioner_Diaries.Table.sql'
    'Gold.Fact_Daily_Targets.Table.sql'
    'Gold.Fact_KPI_Snapshot.Table.sql'
    'Gold.Fact_Targets.Table.sql'
    'Gold.Aggregate_Site_Patient_Current.Table.sql'
    'Gold.Aggregate_Site_Patient_Practitioner_Daily.Table.sql'
    'Gold.Aggregate_Site_Practitioner_Current.Table.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Gold table errors." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# PHASE 7 - Gold stored procedures -modified
# ---------------------------------------------------------------------------

Deploy-Group "10. Gold stored procedures -all (column naming fixes)" @(
    'Gold.usp_Load_Fact_Recalls.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Practice_Sites.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Patients.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Practitioners.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Accounts.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Users.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Payment_Plans.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Treatment_Plans.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Treatments.StoredProcedure.sql'
    'Gold.usp_Load_Dim_Tenants.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Appointments.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Invoice_Items.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Treatment_Appointments.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Treatment_Plan_Items.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Practitioner_Diaries.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Contracts.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Daily_Targets.StoredProcedure.sql'
    'Gold.usp_Load_Fact_Targets.StoredProcedure.sql'
    'Gold.usp_Load_Fact_KPI_Snapshot.StoredProcedure.sql'
    'Gold.usp_Load_Aggregate_Site_Patient_Practitioner_Daily.StoredProcedure.sql'
    'Gold.usp_Load_Aggregate_Site_Patient_Current.StoredProcedure.sql'
    'Gold.usp_Load_Aggregate_Site_Practitioner_Current.StoredProcedure.sql'
)

if ($Errors -gt 0) { Write-Host "`nAborting after Gold SP errors." -ForegroundColor Red; exit 1 }


# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

Write-Host "`n$('-' * 70)"
if ($Errors -eq 0) {
    Write-Host "Schema deploy complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "NEXT STEPS (in order):" -ForegroundColor Yellow
    Write-Host "  1. Regenerate mock API data (from repo root):" -ForegroundColor Yellow
    Write-Host "       python API/generate_data.py" -ForegroundColor Gray
    Write-Host "  2. Redeploy Railway mock API:" -ForegroundColor Yellow
    Write-Host "       railway up  (from API/ folder, or use Railway dashboard)" -ForegroundColor Gray
    Write-Host "  3. Run Fabric pipeline to reload Stage (REQUIRED before Bronze SP data loads):" -ForegroundColor Yellow
    Write-Host "       Fabric workspace > Pipelines > Stage_Ingest_And_Bronze" -ForegroundColor Gray
    Write-Host "       NOTE: Bronze SPs referencing new Stage columns will only" -ForegroundColor Yellow
    Write-Host "       populate data after this step (ni_calculated_*, sent_at, etc.)" -ForegroundColor Yellow
    Write-Host "  4. Reload all layers -Bronze through Gold (run from SSMS against WH_Dentally):" -ForegroundColor Yellow
    Write-Host "       EXEC Audit.usp_Load_All" -ForegroundColor Gray
} else {
    Write-Host "Finished with $Errors error(s) - review output above." -ForegroundColor Red
    exit 1
}
