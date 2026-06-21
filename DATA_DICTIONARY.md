# Data Dictionary - Analytically

Auto-generated from the live schema on 2026-06-18. Reflects the data-minimised model (releases V011-V014). For the privacy classification of these fields see `DPIA.md` and `DPA_SCHEDULE_1.md`; this file is the technical column reference.

- **PBI** views = the presentation layer reports and app users see.
- **Gold** tables = the dimensional model (`Dim_*` dimensions, `Fact_*` facts).

---

## PBI presentation layer (reports / app users)  (36 objects)

### `PBI._Appointment Journey`

| Column | Type |
|---|---|
| Tenant ID | int |
| bk Appointment ID | int |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Practice Site | bigint |
| fk Date Start | bigint |
| Start Time | datetime2 |
| Booking | varchar(50) |
| Appointment Reason | varchar(50) |
| Is Cancelled | bit |
| Is DNA | bit |
| Is Completed | bit |
| Mode | varchar(16) |
| Delay | varchar(19) |
| Next Appointment | varchar(50) |
| Current State | varchar(18) |

### `PBI._Appointments`

| Column | Type |
|---|---|
| pk Appointment | bigint |
| Tenant ID | int |
| bk Appointment ID | int |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Payment Plan | bigint |
| fk Practice Site | bigint |
| fk User | bigint |
| fk Cancellation Reason | bigint |
| fk Date Start | bigint |
| fk Date Pending | bigint |
| fk Date Created | bigint |
| Room ID | varchar(50) |
| State | varchar(50) |
| Reason | varchar(100) |
| Cancellation Reason ID | varchar(50) |
| Arrived At | datetime2 |
| In Surgery At | datetime2 |
| Completed At | datetime2 |
| Confirmed At | datetime2 |
| Cancelled At | datetime2 |
| Did Not Attend At | datetime2 |
| Start Time | datetime2 |
| Finish Time | datetime2 |
| Pending At | datetime2 |
| Is Completed | bit |
| Is Cancelled | bit |
| Is DNA | bit |
| Is Arrived | bit |
| Duration Mins | int |
| Waiting Mins | int |
| In Surgery Mins | int |
| Booking | varchar(50) |
| Appointment Reason | varchar(50) |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Contracts`

| Column | Type |
|---|---|
| pk Contract | bigint |
| Tenant ID | int |
| bk Contract ID | varchar(50) |
| fk Practice Site | bigint |
| fk Date Start | bigint |
| fk Date End | bigint |
| Contract Number | int |
| NHS Location ID | int |
| NHS Site ID | int |
| Site ID | varchar(255) |
| Active | bit |
| PDS Plus | bit |
| Start Date | date |
| End Date | date |
| UDA Target | decimal |
| UDA Value | decimal |
| UOA Target | decimal |
| UOA Value | decimal |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Daily Targets`

| Column | Type |
|---|---|
| pk Daily Target | bigint |
| Tenant ID | int |
| fk Practice Site | bigint |
| fk Practitioner | bigint |
| fk Date | int |
| Metric | varchar(100) |
| Daily Target Value | decimal |
| Variance | decimal |
| DW Created At | datetime2 |

### `PBI._Effective Targets`

| Column | Type |
|---|---|
| pk Effective Target | bigint |
| Tenant ID | int |
| fk Practice Site | bigint |
| Metric | varchar(100) |
| Period Type | varchar(20) |
| Period Value | varchar(20) |
| Effective Target | decimal |
| Effective Variance | decimal |

### `PBI._Invoice Items`

| Column | Type |
|---|---|
| pk Invoice Item | bigint |
| Tenant ID | int |
| bk Invoice Item ID | varchar(255) |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Payment Plan | bigint |
| fk Treatment Plan | bigint |
| fk Account | bigint |
| fk Practice Site | bigint |
| fk User | bigint |
| fk Date Invoice | bigint |
| fk Date Due | bigint |
| fk Date Paid | bigint |
| fk Date Created | bigint |
| Invoice ID | bigint |
| Treatment Plan Item ID | bigint |
| Sundry ID | varchar(255) |
| Item Name | varchar(255) |
| Invoice Reference | int |
| Invoice Payment Terms | varchar(255) |
| Invoice Footnote | varchar(255) |
| Invoice Paid | bit |
| Item Price | decimal |
| Quantity | decimal |
| Total Price | decimal |
| NHS Charge | decimal |
| Invoice Amount | decimal |
| Invoice Amount Outstanding | decimal |
| Invoice NHS Amount | decimal |
| Is Invoice Outstanding | bit |
| Is Discount | bit |
| Aged Debt Band | varchar(11) |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._KPI Snapshot`

| Column | Type |
|---|---|
| pk KPI Snapshot | bigint |
| Tenant ID | int |
| Site ID | varchar(50) |
| fk Practice Site | bigint |
| fk Practitioner | bigint |
| Metric | varchar(100) |
| fk Date | int |
| Snapshot Grain | varchar(10) |
| Value | decimal |
| DW Created At | datetime2 |

### `PBI._NHS Claims`

| Column | Type |
|---|---|
| pk NHS Claim | bigint |
| Tenant ID | int |
| bk NHS Claim ID | varchar(50) |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Treatment Plan | bigint |
| fk Practice Site | bigint |
| fk NHS Contract | bigint |
| fk Date Submitted | bigint |
| fk Date Approval | bigint |
| Claim Status | varchar(50) |
| Sequence Number | int |
| UDA Band | varchar(10) |
| Ortho | bit |
| Continuation Part Number | int |
| Status Comments | varchar(max) |
| Expected UDA | decimal |
| Awarded UDA | decimal |
| Patient Charge | decimal |
| Dentist Charge | decimal |
| Awarded Dentist Charge | decimal |
| NI Calculated Dentist Fee | decimal |
| NI Calculated Patient Fee | decimal |
| SCOT Amount Authorised | decimal |
| SCOT Amount Expected | decimal |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._NHS Contract Week`

| Column | Type |
|---|---|
| pk NHS Contract Week | bigint |
| fk NHS Contract | bigint |
| fk Date Week Start | int |
| Tenant ID | int |
| Financial Year | smallint |
| Financial Week | smallint |
| Working Days In Week | smallint |
| Total Working Days In Year | smallint |
| Pro Rata UDA Target | decimal |
| DW Created At | datetime2 |

### `PBI._Payments`

| Column | Type |
|---|---|
| pk Payment | bigint |
| Tenant ID | int |
| bk Payment ID | int |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Practice Site | bigint |
| fk Date Payment | bigint |
| Payment Method | varchar(100) |
| Payment Amount | decimal |
| Is Deposit | bit |
| Deposit Amount | decimal |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Practitioner Diaries`

| Column | Type |
|---|---|
| pk Practitioner Diary | bigint |
| Tenant ID | int |
| bk Practitioner Diary ID | varchar(50) |
| fk Practitioner | bigint |
| fk Date Day | bigint |
| Day Date | date |
| Start Time | time |
| End Time | time |
| Unavailable | bit |
| Session Duration Mins | int |
| Total Break Mins | int |
| Available Clinical Mins | int |
| Break Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Recalls`

| Column | Type |
|---|---|
| pk Recall | bigint |
| Tenant ID | int |
| bk Recall ID | varchar(50) |
| fk Patient | bigint |
| fk Date Due | bigint |
| fk Date Run | bigint |
| fk Date First Reminder | bigint |
| fk Date Second Reminder | bigint |
| fk Date Last Reminded | bigint |
| Appointment ID | varchar(50) |
| Recall Type | varchar(100) |
| Recall Method | varchar(100) |
| Status | varchar(100) |
| Workflow Status | varchar(100) |
| Workflow Stage ID | varchar(50) |
| First Reminder Type | varchar(100) |
| Second Reminder Type | varchar(100) |
| Latest Reminder Type | varchar(100) |
| Times Contacted | int |
| Due Date | date |
| Run Date | date |
| Days Overdue | int |
| Is In Scope | bit |
| Is Reminder Sent | bit |
| Is Booked Via Recall | bit |
| Is Booked | bit |
| Retention Outlook In Scope | int |
| Retention Outlook Booked | int |
| Overdue Band | varchar(20) |
| Recall Status | varchar(20) |
| fk Date Appt Booked | bigint |
| Appt State | varchar(50) |
| Appt Booked Via API | bit |
| Appt Start Time | datetime2 |
| Days Recall To Booking | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Targets`

| Column | Type |
|---|---|
| pk target | bigint |
| Tenant ID | int |
| bk target id | bigint |
| fk Practice Site | bigint |
| fk Practitioner | bigint |
| fk Date | bigint |
| Metric | varchar(100) |
| Period Type | varchar(20) |
| Period Value | varchar(20) |
| Target Value | decimal |
| Variance | decimal |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Treatment Appointments`

| Column | Type |
|---|---|
| pk Treatment Appointment | bigint |
| Tenant ID | int |
| bk Treatment Appointment ID | varchar(50) |
| fk Patient | bigint |
| fk Treatment Plan | bigint |
| fk Date Appointment | bigint |
| fk Date Created | bigint |
| Appointment ID | int |
| Treatment Plan ID | int |
| Position | int |
| Bookable | bit |
| Created At | datetime2 |
| Updated At | datetime2 |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI._Treatment Plan Items`

| Column | Type |
|---|---|
| pk Treatment Plan Item | bigint |
| Tenant ID | int |
| bk Treatment Plan Item ID | varchar(50) |
| fk Treatment Plan | bigint |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Payment Plan | bigint |
| fk Treatment | bigint |
| fk Date Created | bigint |
| fk Date Completed | bigint |
| fk Date Updated | bigint |
| Treatment Plan ID | int |
| Invoice ID | int |
| Treatment Appointment ID | varchar(50) |
| Referrer ID | int |
| Nomenclature | varchar(255) |
| NHS Treatment Cat | varchar(50) |
| UDA Band | varchar(50) |
| Region | varchar(100) |
| Position | int |
| Base Chart | bit |
| Completed | bit |
| Charged | bit |
| Appear On Invoice | bit |
| Price | decimal |
| Duration Mins | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.Aggregate Site Patient Current`

| Column | Type |
|---|---|
| pk Site Patient Current | bigint |
| fk Site | bigint |
| fk Patient | bigint |
| Tenant ID | int |
| Retained Patients | bit |
| Active Patients | bit |
| Recall Due | bit |
| Recall Sent | bit |
| Future Appointment | bit |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.Aggregate Site Patient Practitioner Daily`

| Column | Type |
|---|---|
| pk Site Patient Practitioner Daily | bigint |
| fk Site | bigint |
| fk Patient | bigint |
| fk Practitioner | bigint |
| fk Date | bigint |
| Tenant ID | int |
| NHS UDAs | decimal |
| NHS UOAs | decimal |
| Appointments | int |
| DNA Appointments | int |
| BBYL Appointments | int |
| NHS Revenue | decimal |
| Private Revenue | decimal |
| Open Treatment Plan | int |
| Future Appointment | bit |
| Exam Count | int |
| Treatment Count | int |
| New Patient | bit |
| Worked Hours | decimal |
| Appointment Hours | decimal |
| Cancelled Appointments | int |
| Short Notice Cancellations | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.Aggregate Site Practitioner Current`

| Column | Type |
|---|---|
| pk Site Practitioner Current | bigint |
| fk Site | bigint |
| fk Practitioner | bigint |
| Tenant ID | int |
| Days Until Next 30 Mins | int |
| Days Until Next 1 Hour Free | int |
| Next 7 Days Available Mins | int |
| Next 7 Days Booked Mins | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.Application Users`

| Column | Type |
|---|---|
| User UPN | varchar(255) |
| Tenant ID | int |

### `PBI.Invoice_Discount`

| Column | Type |
|---|---|
| Tenant ID | int |
| Invoice ID | int |

### `PBI.List Accounts`

| Column | Type |
|---|---|
| pk Account | bigint |
| Tenant ID | int |
| Account ID | int |
| Patient ID | int |
| Patient Name | varchar(255) |
| Current Balance | decimal |
| Opening Balance | decimal |
| Planned NHS Treatment Value | decimal |
| Planned Private Treatment Value | decimal |
| Account Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Acquisition Sources`

| Column | Type |
|---|---|
| pk Acquisition Source | bigint |
| Tenant ID | int |
| Acquisition Source ID | varchar(50) |
| Active | bit |
| Name | varchar(255) |
| Standard Acquisition Source | varchar(100) |
| Acquisition Source Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Cancellation Reasons`

| Column | Type |
|---|---|
| pk Cancellation Reason | bigint |
| Tenant ID | int |
| bk Cancellation Reason ID | varchar(50) |
| Is Active | bit |
| Reason | varchar(255) |
| Standard Cancellation Reason | varchar(100) |
| Reason Type | varchar(50) |
| Is Short Notice | bit |
| Cancellation Reason Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Date`

| Column | Type |
|---|---|
| pk Date | int |
| Full Date | date |
| Day Name | varchar(10) |
| Day Of Week | smallint |
| Day Of Month | smallint |
| Day Of Year | smallint |
| Week Of Year | smallint |
| Week Of Month | smallint |
| Calendar Year Week | int |
| Week Commencing Date | date |
| Week Ending Date | date |
| Month Number | smallint |
| Month Name | varchar(10) |
| Month Name Short | varchar(3) |
| Month Year | varchar(10) |
| Month Commencing Date | date |
| Month Ending Date | date |
| Calendar Quarter | smallint |
| Calendar Quarter Name | varchar(2) |
| Calendar Year | smallint |
| Calendar Year Month | int |
| Calendar Year Quarter | varchar(7) |
| Relative Day | int |
| Relative Week | int |
| Relative Month | int |
| Relative Quarter | int |
| Relative Year | int |
| Financial Year | smallint |
| Financial Year Name | char(10) |
| Financial Quarter | smallint |
| Financial Quarter Name | varchar(11) |
| Financial Month | smallint |
| Financial Month Name | varchar(20) |
| Financial Week | smallint |
| Financial Day Of Year | smallint |
| Relative Financial Day | int |
| Relative Financial Week | int |
| Relative Financial Month | int |
| Relative Financial Quarter | int |
| Relative Financial Year | int |
| Is Weekend | bit |
| Is Leap Year | bit |
| Is England Wales Bank Holiday | bit |
| Is Scotland Bank Holiday | bit |
| Is Working Day England | bit |

### `PBI.List Date Grouping`

| Column | Type |
|---|---|
| Date Grouping | varchar(20) |
| fk Date | int |
| fk Date Previous Year | int |

### `PBI.List NHS Contracts`

| Column | Type |
|---|---|
| pk NHS Contract | bigint |
| Tenant ID | int |
| bk Contract ID | varchar(50) |
| Contract Number | varchar(50) |
| Contract Name | varchar(255) |
| Site ID | varchar(50) |
| Active | bit |
| PDS Plus | bit |
| NHS Location ID | varchar(50) |
| NHS Site ID | varchar(50) |
| Start Date | date |
| End Date | date |
| UDA Target | decimal |
| UDA Value | decimal |
| UOA Target | decimal |
| UOA Value | decimal |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Patients`

| Column | Type |
|---|---|
| pk Patient | bigint |
| Tenant ID | int |
| Patient ID | int |
| Account ID | int |
| First Name | varchar(100) |
| Last Name | varchar(100) |
| Preferred Name | varchar(100) |
| Full Name | varchar(255) |
| Email Address | varchar(255) |
| Home Phone | varchar(50) |
| Mobile Phone | varchar(50) |
| Is Email Missing | bit |
| Is Phone Missing | bit |
| Active | bit |
| Payment Plan ID | int |
| Site ID | varchar(50) |
| Acquisition Source ID | varchar(50) |
| fk Acquisition Source | bigint |
| Dentist Practitioner ID | int |
| Hygienist Practitioner ID | int |
| Dentist Recall Date | date |
| Dentist Recall Interval Months | int |
| Hygienist Recall Date | date |
| Hygienist Recall Interval Months | int |
| Recall Method | varchar(100) |
| Marketing Consent | varchar(255) |
| First Appointment Date | date |
| Last Appointment Date | date |
| Next Appointment Date | date |
| First Exam Date | date |
| Last Exam Date | date |
| Next Exam Date | date |
| Last Scale Polish Date | date |
| Next Scale Polish Date | date |
| Last FTA Date | date |
| Last Cancelled Appointment Date | date |
| Total Paid | decimal |
| Total Invoiced | decimal |
| Patient Created Date | date |
| Patient Updated Date | date |
| Patient Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Payment Plans`

| Column | Type |
|---|---|
| pk Payment Plan | bigint |
| Tenant ID | int |
| Payment Plan ID | int |
| Payment Plan Name | varchar(255) |
| Standard Payment Plan | varchar(100) |
| Patient Friendly Name | varchar(255) |
| Active | bit |
| Colour | varchar(20) |
| Site ID | varchar(50) |
| Dentist Recall Interval Months | int |
| Hygienist Recall Interval Months | int |
| Emergency Duration Mins | int |
| Exam Duration Mins | int |
| Exam Scale Polish Duration Mins | int |
| Scale Polish Duration Mins | int |
| Created Date | datetime2 |
| Payment Plan Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Practice Sites`

| Column | Type |
|---|---|
| pk Practice Site | bigint |
| Tenant ID | int |
| Site ID | varchar(50) |
| Site Name | varchar(255) |
| Site Active | bit |
| Site Address Line 1 | varchar(255) |
| Site Address Line 2 | varchar(255) |
| Site Town | varchar(100) |
| Site Postcode | varchar(20) |
| Site Phone | varchar(50) |
| Site Website | varchar(255) |
| Site Logo URL | varchar(255) |
| Site Default Payment Plan ID | int |
| Monday Open | time |
| Monday Close | time |
| Tuesday Open | time |
| Tuesday Close | time |
| Wednesday Open | time |
| Wednesday Close | time |
| Thursday Open | time |
| Thursday Close | time |
| Friday Open | time |
| Friday Close | time |
| Practice ID | varchar(255) |
| Practice Name | varchar(255) |
| Practice Address Line 1 | varchar(255) |
| Practice Address Line 2 | varchar(255) |
| Practice Town | varchar(100) |
| Practice Postcode | varchar(20) |
| Practice Phone | varchar(50) |
| Practice Email | varchar(255) |
| Practice Website | varchar(255) |
| Practice NHS | bit |
| Practice Time Zone | varchar(100) |
| Practice Site Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Practitioners`

| Column | Type |
|---|---|
| pk Practitioner | bigint |
| Tenant ID | int |
| Practitioner ID | int |
| User ID | int |
| Title | varchar(50) |
| First Name | varchar(100) |
| Middle Name | varchar(100) |
| Last Name | varchar(100) |
| Full Name | varchar(255) |
| Email | varchar(255) |
| Mobile Phone | varchar(50) |
| Role | varchar(100) |
| Permission Level | int |
| Active | bit |
| Colour | varchar(50) |
| GDC Number | varchar(50) |
| NHS Number | varchar(50) |
| Site ID | varchar(50) |
| Default Contract ID | varchar(255) |
| Contract Targets String | varchar(255) |
| Image URL | varchar(255) |
| Last Login Date | date |
| Created Date | datetime2 |
| Updated Date | datetime2 |
| Practitioner Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Tenants`

| Column | Type |
|---|---|
| pk Tenant | bigint |
| Tenant ID | int |
| Tenant Name | varchar(255) |
| Is Active | bit |
| Tenant Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Treatment Plans`

| Column | Type |
|---|---|
| pk Treatment Plan | bigint |
| Tenant ID | int |
| Treatment Plan ID | int |
| Nickname | varchar(255) |
| Patient ID | int |
| Practitioner ID | int |
| Completed | bit |
| Start Date | date |
| End Date | date |
| Completed Date | datetime2 |
| Last Completed Date | date |
| NHS UDA Value | decimal |
| NHS Completed UDA Value | decimal |
| Private Treatment Value | decimal |
| Created Date | datetime2 |
| Updated Date | datetime2 |
| Treatment Plan Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Treatments`

| Column | Type |
|---|---|
| pk Treatment | bigint |
| Tenant ID | int |
| Treatment ID | int |
| Treatment Code | varchar(50) |
| Nomenclature | varchar(255) |
| Region | varchar(100) |
| UDA Band | int |
| NHS Treatment Cat | int |
| Treatment Category ID | int |
| Treatment Category Name | varchar(255) |
| Standard Treatment Category | varchar(100) |
| Created Date | datetime2 |
| Updated Date | datetime2 |
| Treatment Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.List Users`

| Column | Type |
|---|---|
| pk User | bigint |
| Tenant ID | int |
| bk User ID | int |
| Title | varchar(50) |
| First Name | varchar(100) |
| Middle Name | varchar(100) |
| Last Name | varchar(100) |
| Full Name | varchar(255) |
| Email | varchar(255) |
| Mobile Phone | varchar(50) |
| Role | varchar(100) |
| Permission Level | int |
| Practice ID | varchar(255) |
| Site ID | varchar(255) |
| Image URL | varchar(255) |
| Last Login Date | date |
| Created Date | datetime2 |
| Updated Date | datetime2 |
| User Count | int |
| DW Created At | datetime2 |
| DW Updated At | datetime2 |
| Is Current | bit |

### `PBI.Load_Watermark`

| Column | Type |
|---|---|
| Entity Name | varchar(128) |
| Last Loaded At | datetime2 |
| DW Updated At | datetime2 |

### `PBI.Payment_Deposit`

| Column | Type |
|---|---|
| Tenant ID | int |
| Payment ID | int |
| Deposit Amount | decimal |

---

## Gold dimensional model  (38 objects)

### `Gold.Aggregate_Site_Patient_Current`

| Column | Type |
|---|---|
| pk_Site_Patient_Current | bigint |
| fk_Site | bigint |
| fk_Patient | bigint |
| Tenant_ID | int |
| Retained_Patients | bit |
| Active_Patients | bit |
| Recall_Due | bit |
| Recall_Sent | bit |
| Future_Appointment | bit |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Aggregate_Site_Patient_Practitioner_Daily`

| Column | Type |
|---|---|
| pk_Site_Patient_Practitioner_Daily | bigint |
| fk_Site | bigint |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Date | bigint |
| Tenant_ID | int |
| NHS_UDAs | decimal |
| NHS_UOAs | decimal |
| Appointments | int |
| DNA_Appointments | int |
| BBYL_Appointments | int |
| NHS_Revenue | decimal |
| Private_Revenue | decimal |
| Open_Treatment_Plan | int |
| Future_Appointment | bit |
| Exam_Count | int |
| Treatment_Count | int |
| New_Patient | bit |
| Worked_Hours | decimal |
| Appointment_Hours | decimal |
| Cancelled_Appointments | int |
| Short_Notice_Cancellations | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Aggregate_Site_Practitioner_Current`

| Column | Type |
|---|---|
| pk_Site_Practitioner_Current | bigint |
| fk_Site | bigint |
| fk_Practitioner | bigint |
| Tenant_ID | int |
| Days_Until_Next_30_Mins | int |
| Days_Until_Next_1_Hour_Free | int |
| Next_7_Days_Available_Mins | int |
| Next_7_Days_Booked_Mins | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Accounts`

| Column | Type |
|---|---|
| pk_Account | bigint |
| Tenant_ID | int |
| Account_ID | int |
| Patient_ID | int |
| Patient_Name | varchar(255) |
| Current_Balance | decimal |
| Opening_Balance | decimal |
| Planned_NHS_Treatment_Value | decimal |
| Planned_Private_Treatment_Value | decimal |
| Account_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Acquisition_Sources`

| Column | Type |
|---|---|
| pk_Acquisition_Source | bigint |
| Tenant_ID | int |
| Acquisition_Source_ID | varchar(50) |
| Active | bit |
| Name | varchar(255) |
| Standard_Acquisition_Source | varchar(100) |
| Acquisition_Source_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Cancellation_Reasons`

| Column | Type |
|---|---|
| pk_Cancellation_Reason | bigint |
| Tenant_ID | int |
| bk_Cancellation_Reason_ID | varchar(50) |
| Is_Active | bit |
| Reason | varchar(255) |
| Standard_Cancellation_Reason | varchar(100) |
| Reason_Type | varchar(50) |
| Is_Short_Notice | bit |
| Cancellation_Reason_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Date`

| Column | Type |
|---|---|
| pk_Date | int |
| Full_Date | date |
| Day_Name | varchar(10) |
| Day_Of_Week | smallint |
| Day_Of_Month | smallint |
| Day_Of_Year | smallint |
| Week_Of_Year | smallint |
| Week_Of_Month | smallint |
| Calendar_Year_Week | int |
| Week_Commencing_Date | date |
| Week_Ending_Date | date |
| Month_Number | smallint |
| Month_Name | varchar(10) |
| Month_Name_Short | varchar(3) |
| Month_Year | varchar(10) |
| Month_Commencing_Date | date |
| Month_Ending_Date | date |
| Calendar_Quarter | smallint |
| Calendar_Quarter_Name | varchar(2) |
| Calendar_Year | smallint |
| Calendar_Year_Month | int |
| Calendar_Year_Quarter | varchar(7) |
| Relative_Day | int |
| Relative_Week | int |
| Relative_Month | int |
| Relative_Quarter | int |
| Relative_Year | int |
| Financial_Year | smallint |
| Financial_Year_Name | char(10) |
| Financial_Quarter | smallint |
| Financial_Quarter_Name | varchar(11) |
| Financial_Month | smallint |
| Financial_Month_Name | varchar(20) |
| Financial_Week | smallint |
| Financial_Day_Of_Year | smallint |
| Relative_Financial_Day | int |
| Relative_Financial_Week | int |
| Relative_Financial_Month | int |
| Relative_Financial_Quarter | int |
| Relative_Financial_Year | int |
| Is_Weekend | bit |
| Is_Leap_Year | bit |
| Is_England_Wales_Bank_Holiday | bit |
| Is_Scotland_Bank_Holiday | bit |
| Is_Working_Day_England | bit |

### `Gold.Dim_Date_Grouping`

| Column | Type |
|---|---|
| Date_Grouping | varchar(20) |
| fk_Date | int |
| fk_Date_Previous_Year | int |

### `Gold.Dim_NHS_Contracts`

| Column | Type |
|---|---|
| pk_NHS_Contract | bigint |
| Tenant_ID | int |
| bk_Contract_ID | varchar(50) |
| Contract_Number | varchar(50) |
| Contract_Name | varchar(255) |
| Site_ID | varchar(50) |
| Active | bit |
| PDS_Plus | bit |
| NHS_Location_ID | varchar(50) |
| NHS_Site_ID | varchar(50) |
| Start_Date | date |
| End_Date | date |
| UDA_Target | decimal |
| UDA_Value | decimal |
| UOA_Target | decimal |
| UOA_Value | decimal |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Patients`

| Column | Type |
|---|---|
| pk_Patient | bigint |
| Tenant_ID | int |
| Patient_ID | int |
| Account_ID | int |
| First_Name | varchar(100) |
| Last_Name | varchar(100) |
| Preferred_Name | varchar(100) |
| Full_Name | varchar(255) |
| Email_Address | varchar(255) |
| Home_Phone | varchar(50) |
| Mobile_Phone | varchar(50) |
| Is_Email_Missing | bit |
| Is_Phone_Missing | bit |
| Active | bit |
| Payment_Plan_ID | int |
| Site_ID | varchar(50) |
| Acquisition_Source_ID | varchar(50) |
| fk_Acquisition_Source | bigint |
| Dentist_Practitioner_ID | int |
| Hygienist_Practitioner_ID | int |
| Dentist_Recall_Date | date |
| Dentist_Recall_Interval_Months | int |
| Hygienist_Recall_Date | date |
| Hygienist_Recall_Interval_Months | int |
| Recall_Method | varchar(100) |
| Marketing_Consent | varchar(255) |
| First_Appointment_Date | date |
| Last_Appointment_Date | date |
| Next_Appointment_Date | date |
| First_Exam_Date | date |
| Last_Exam_Date | date |
| Next_Exam_Date | date |
| Last_Scale_Polish_Date | date |
| Next_Scale_Polish_Date | date |
| Last_FTA_Date | date |
| Last_Cancelled_Appointment_Date | date |
| Total_Paid | decimal |
| Total_Invoiced | decimal |
| Patient_Created_Date | date |
| Patient_Updated_Date | date |
| Patient_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Payment_Plans`

| Column | Type |
|---|---|
| pk_Payment_Plan | bigint |
| Tenant_ID | int |
| Payment_Plan_ID | int |
| Payment_Plan_Name | varchar(255) |
| Standard_Payment_Plan | varchar(100) |
| Patient_Friendly_Name | varchar(255) |
| Active | bit |
| Colour | varchar(20) |
| Site_ID | varchar(50) |
| Dentist_Recall_Interval_Months | int |
| Hygienist_Recall_Interval_Months | int |
| Emergency_Duration_Mins | int |
| Exam_Duration_Mins | int |
| Exam_Scale_Polish_Duration_Mins | int |
| Scale_Polish_Duration_Mins | int |
| Created_Date | datetime2 |
| Payment_Plan_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Practice_Sites`

| Column | Type |
|---|---|
| pk_Practice_Site | bigint |
| Tenant_ID | int |
| Site_ID | varchar(50) |
| Site_Name | varchar(255) |
| Site_Active | bit |
| Site_Address_Line_1 | varchar(255) |
| Site_Address_Line_2 | varchar(255) |
| Site_Town | varchar(100) |
| Site_Postcode | varchar(20) |
| Site_Phone | varchar(50) |
| Site_Website | varchar(255) |
| Site_Logo_URL | varchar(255) |
| Site_Default_Payment_Plan_ID | int |
| Monday_Open | time |
| Monday_Close | time |
| Tuesday_Open | time |
| Tuesday_Close | time |
| Wednesday_Open | time |
| Wednesday_Close | time |
| Thursday_Open | time |
| Thursday_Close | time |
| Friday_Open | time |
| Friday_Close | time |
| Practice_ID | varchar(255) |
| Practice_Name | varchar(255) |
| Practice_Address_Line_1 | varchar(255) |
| Practice_Address_Line_2 | varchar(255) |
| Practice_Town | varchar(100) |
| Practice_Postcode | varchar(20) |
| Practice_Phone | varchar(50) |
| Practice_Email | varchar(255) |
| Practice_Website | varchar(255) |
| Practice_NHS | bit |
| Practice_Time_Zone | varchar(100) |
| Practice_Site_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Practitioners`

| Column | Type |
|---|---|
| pk_Practitioner | bigint |
| Tenant_ID | int |
| Practitioner_ID | int |
| User_ID | int |
| Title | varchar(50) |
| First_Name | varchar(100) |
| Middle_Name | varchar(100) |
| Last_Name | varchar(100) |
| Full_Name | varchar(255) |
| Email | varchar(255) |
| Mobile_Phone | varchar(50) |
| Role | varchar(100) |
| Permission_Level | int |
| Active | bit |
| Colour | varchar(50) |
| GDC_Number | varchar(50) |
| NHS_Number | varchar(50) |
| Site_ID | varchar(50) |
| Default_Contract_ID | varchar(255) |
| Contract_Targets_String | varchar(255) |
| Image_URL | varchar(255) |
| Last_Login_Date | date |
| Created_Date | datetime2 |
| Updated_Date | datetime2 |
| Practitioner_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Tenants`

| Column | Type |
|---|---|
| pk_Tenant | bigint |
| Tenant_ID | int |
| Tenant_Name | varchar(255) |
| Is_Active | bit |
| Tenant_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Treatment_Plans`

| Column | Type |
|---|---|
| pk_Treatment_Plan | bigint |
| Tenant_ID | int |
| Treatment_Plan_ID | int |
| Nickname | varchar(255) |
| Patient_ID | int |
| Practitioner_ID | int |
| Completed | bit |
| Start_Date | date |
| End_Date | date |
| Completed_Date | datetime2 |
| Last_Completed_Date | date |
| NHS_UDA_Value | decimal |
| NHS_Completed_UDA_Value | decimal |
| Private_Treatment_Value | decimal |
| Created_Date | datetime2 |
| Updated_Date | datetime2 |
| Treatment_Plan_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Treatments`

| Column | Type |
|---|---|
| pk_Treatment | bigint |
| Tenant_ID | int |
| Treatment_ID | int |
| Treatment_Code | varchar(50) |
| Nomenclature | varchar(255) |
| Region | varchar(100) |
| UDA_Band | int |
| NHS_Treatment_Cat | int |
| Treatment_Category_ID | int |
| Treatment_Category_Name | varchar(255) |
| Standard_Treatment_Category | varchar(100) |
| Created_Date | datetime2 |
| Updated_Date | datetime2 |
| Treatment_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Dim_Users`

| Column | Type |
|---|---|
| pk_User | bigint |
| Tenant_ID | int |
| bk_User_ID | int |
| Title | varchar(50) |
| First_Name | varchar(100) |
| Middle_Name | varchar(100) |
| Last_Name | varchar(100) |
| Full_Name | varchar(255) |
| Email | varchar(255) |
| Mobile_Phone | varchar(50) |
| Role | varchar(100) |
| Permission_Level | int |
| Practice_ID | varchar(255) |
| Site_ID | varchar(255) |
| Image_URL | varchar(255) |
| Last_Login_Date | date |
| Created_Date | datetime2 |
| Updated_Date | datetime2 |
| User_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |
| Is_Current | bit |

### `Gold.Fact_Appointment_Journey`

| Column | Type |
|---|---|
| pk_Appointment_Journey | bigint |
| Tenant_ID | int |
| bk_Appointment_ID | int |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Practice_Site | bigint |
| fk_Date_Start | bigint |
| Start_Time | datetime2 |
| Booking | varchar(50) |
| Appointment_Reason | varchar(50) |
| Is_Cancelled | bit |
| Is_DNA | bit |
| Is_Completed | bit |
| fk_Appointment_Next | int |
| fk_Appointment_Exam | int |
| fk_Appointment_Hygiene | int |
| fk_Appointment_Not_Hygiene | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Appointments`

| Column | Type |
|---|---|
| pk_Appointment | bigint |
| Tenant_ID | int |
| bk_Appointment_ID | int |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Payment_Plan | bigint |
| fk_Practice_Site | bigint |
| fk_User | bigint |
| fk_Cancellation_Reason | bigint |
| fk_Date_Start | bigint |
| fk_Date_Pending | bigint |
| fk_Date_Created | bigint |
| Room_ID | varchar(50) |
| State | varchar(50) |
| Reason | varchar(100) |
| Cancellation_Reason_ID | varchar(50) |
| Arrived_At | datetime2 |
| In_Surgery_At | datetime2 |
| Completed_At | datetime2 |
| Confirmed_At | datetime2 |
| Cancelled_At | datetime2 |
| Did_Not_Attend_At | datetime2 |
| Start_Time | datetime2 |
| Finish_Time | datetime2 |
| Pending_At | datetime2 |
| Is_Completed | bit |
| Is_Cancelled | bit |
| Is_DNA | bit |
| Is_Arrived | bit |
| Duration_Mins | int |
| Waiting_Mins | int |
| In_Surgery_Mins | int |
| Booking | varchar(50) |
| Appointment_Reason | varchar(50) |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Contracts`

| Column | Type |
|---|---|
| pk_Contract | bigint |
| Tenant_ID | int |
| bk_Contract_ID | varchar(50) |
| fk_Practice_Site | bigint |
| fk_Date_Start | bigint |
| fk_Date_End | bigint |
| Contract_Number | int |
| NHS_Location_ID | int |
| NHS_Site_ID | int |
| Site_ID | varchar(255) |
| Active | bit |
| PDS_Plus | bit |
| Start_Date | date |
| End_Date | date |
| UDA_Target | decimal |
| UDA_Value | decimal |
| UOA_Target | decimal |
| UOA_Value | decimal |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Daily_Targets`

| Column | Type |
|---|---|
| pk_Daily_Target | bigint |
| Tenant_ID | int |
| fk_Practice_Site | bigint |
| fk_Practitioner | bigint |
| fk_Date | int |
| Metric | varchar(100) |
| Daily_Target_Value | decimal |
| Variance | decimal |
| DW_Created_At | datetime2 |

### `Gold.Fact_Effective_Targets`

| Column | Type |
|---|---|
| pk_Effective_Target | bigint |
| Tenant_ID | int |
| fk_Practice_Site | bigint |
| Metric | varchar(100) |
| Period_Type | varchar(20) |
| Period_Value | varchar(20) |
| Effective_Target | decimal |
| Effective_Variance | decimal |

### `Gold.Fact_Invoice_Items`

| Column | Type |
|---|---|
| pk_Invoice_Item | bigint |
| Tenant_ID | int |
| bk_Invoice_Item_ID | varchar(255) |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Payment_Plan | bigint |
| fk_Treatment_Plan | bigint |
| fk_Account | bigint |
| fk_Practice_Site | bigint |
| fk_User | bigint |
| fk_Date_Invoice | bigint |
| fk_Date_Due | bigint |
| fk_Date_Paid | bigint |
| fk_Date_Created | bigint |
| Invoice_ID | bigint |
| Treatment_Plan_Item_ID | bigint |
| Sundry_ID | varchar(255) |
| Item_Name | varchar(255) |
| Invoice_Reference | int |
| Invoice_Payment_Terms | varchar(255) |
| Invoice_Footnote | varchar(255) |
| Invoice_Paid | bit |
| Item_Price | decimal |
| Quantity | decimal |
| Total_Price | decimal |
| NHS_Charge | decimal |
| Invoice_Amount | decimal |
| Invoice_Amount_Outstanding | decimal |
| Invoice_NHS_Amount | decimal |
| Is_Invoice_Outstanding | bit |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_KPI_Snapshot`

| Column | Type |
|---|---|
| pk_KPI_Snapshot | bigint |
| Tenant_ID | int |
| Site_ID | varchar(50) |
| fk_Practice_Site | bigint |
| fk_Practitioner | bigint |
| Metric | varchar(100) |
| fk_Date | int |
| Snapshot_Grain | varchar(10) |
| Value | decimal |
| DW_Created_At | datetime2 |

### `Gold.Fact_NHS_Claims`

| Column | Type |
|---|---|
| pk_NHS_Claim | bigint |
| Tenant_ID | int |
| bk_NHS_Claim_ID | varchar(50) |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Treatment_Plan | bigint |
| fk_Practice_Site | bigint |
| fk_NHS_Contract | bigint |
| fk_Date_Submitted | bigint |
| fk_Date_Approval | bigint |
| Claim_Status | varchar(50) |
| Sequence_Number | int |
| UDA_Band | varchar(10) |
| Ortho | bit |
| Continuation_Part_Number | int |
| Status_Comments | varchar(max) |
| Expected_UDA | decimal |
| Awarded_UDA | decimal |
| Patient_Charge | decimal |
| Dentist_Charge | decimal |
| Awarded_Dentist_Charge | decimal |
| NI_Calculated_Dentist_Fee | decimal |
| NI_Calculated_Patient_Fee | decimal |
| SCOT_Amount_Authorised | decimal |
| SCOT_Amount_Expected | decimal |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_NHS_Contract_Week`

| Column | Type |
|---|---|
| pk_NHS_Contract_Week | bigint |
| fk_NHS_Contract | bigint |
| fk_Date_Week_Start | int |
| Tenant_ID | int |
| Financial_Year | smallint |
| Financial_Week | smallint |
| Working_Days_In_Week | smallint |
| Total_Working_Days_In_Year | smallint |
| Pro_Rata_UDA_Target | decimal |
| DW_Created_At | datetime2 |

### `Gold.Fact_Payments`

| Column | Type |
|---|---|
| pk_Payment | bigint |
| Tenant_ID | int |
| bk_Payment_ID | int |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Practice_Site | bigint |
| fk_Date_Payment | bigint |
| Payment_Method | varchar(100) |
| Payment_Amount | decimal |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Practitioner_Diaries`

| Column | Type |
|---|---|
| pk_Practitioner_Diary | bigint |
| Tenant_ID | int |
| bk_Practitioner_Diary_ID | varchar(50) |
| fk_Practitioner | bigint |
| fk_Date_Day | bigint |
| Day_Date | date |
| Start_Time | time |
| End_Time | time |
| Unavailable | bit |
| Session_Duration_Mins | int |
| Total_Break_Mins | int |
| Available_Clinical_Mins | int |
| Break_Count | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Recalls`

| Column | Type |
|---|---|
| pk_Recall | bigint |
| Tenant_ID | int |
| bk_Recall_ID | varchar(50) |
| fk_Patient | bigint |
| fk_Date_Due | bigint |
| fk_Date_Run | bigint |
| fk_Date_First_Reminder | bigint |
| fk_Date_Second_Reminder | bigint |
| fk_Date_Last_Reminded | bigint |
| Appointment_ID | varchar(50) |
| Recall_Type | varchar(100) |
| Recall_Method | varchar(100) |
| Status | varchar(100) |
| Workflow_Status | varchar(100) |
| Workflow_Stage_ID | varchar(50) |
| First_Reminder_Type | varchar(100) |
| Second_Reminder_Type | varchar(100) |
| Latest_Reminder_Type | varchar(100) |
| Times_Contacted | int |
| Due_Date | date |
| Run_Date | date |
| Days_Overdue | int |
| Is_In_Scope | bit |
| Is_Reminder_Sent | bit |
| Is_Booked_Via_Recall | bit |
| Is_Booked | bit |
| Retention_Outlook_In_Scope | int |
| Retention_Outlook_Booked | int |
| Overdue_Band | varchar(20) |
| Recall_Status | varchar(20) |
| fk_Date_Appt_Booked | bigint |
| Appt_State | varchar(50) |
| Appt_Booked_Via_API | bit |
| Appt_Start_Time | datetime2 |
| Days_Recall_To_Booking | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Targets`

| Column | Type |
|---|---|
| pk_target | bigint |
| Tenant_ID | int |
| bk_target_id | bigint |
| fk_Practice_Site | bigint |
| fk_Practitioner | bigint |
| fk_Date | bigint |
| Metric | varchar(100) |
| Period_Type | varchar(20) |
| Period_Value | varchar(20) |
| Target_Value | decimal |
| Variance | decimal |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Treatment_Appointments`

| Column | Type |
|---|---|
| pk_Treatment_Appointment | bigint |
| Tenant_ID | int |
| bk_Treatment_Appointment_ID | varchar(50) |
| fk_Patient | bigint |
| fk_Treatment_Plan | bigint |
| fk_Date_Appointment | bigint |
| fk_Date_Created | bigint |
| Appointment_ID | int |
| Treatment_Plan_ID | int |
| Position | int |
| Bookable | bit |
| Created_At | datetime2 |
| Updated_At | datetime2 |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Fact_Treatment_Plan_Items`

| Column | Type |
|---|---|
| pk_Treatment_Plan_Item | bigint |
| Tenant_ID | int |
| bk_Treatment_Plan_Item_ID | varchar(50) |
| fk_Treatment_Plan | bigint |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Payment_Plan | bigint |
| fk_Treatment | bigint |
| fk_Date_Created | bigint |
| fk_Date_Completed | bigint |
| fk_Date_Updated | bigint |
| Treatment_Plan_ID | int |
| Invoice_ID | int |
| Treatment_Appointment_ID | varchar(50) |
| Referrer_ID | int |
| Nomenclature | varchar(255) |
| NHS_Treatment_Cat | varchar(50) |
| UDA_Band | varchar(50) |
| Region | varchar(100) |
| Position | int |
| Base_Chart | bit |
| Completed | bit |
| Charged | bit |
| Appear_On_Invoice | bit |
| Price | decimal |
| Duration_Mins | int |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Invoice_Discount`

| Column | Type |
|---|---|
| Tenant_ID | int |
| Invoice_ID | int |

### `Gold.Load_Watermark`

| Column | Type |
|---|---|
| Entity_Name | varchar(128) |
| Last_Loaded_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.Payment_Deposit`

| Column | Type |
|---|---|
| Tenant_ID | int |
| Payment_ID | int |
| Deposit_Amount | decimal |

### `Gold.vw_Fact_Appointment_Journey`

| Column | Type |
|---|---|
| Tenant_ID | int |
| bk_Appointment_ID | int |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Practice_Site | bigint |
| fk_Date_Start | bigint |
| Start_Time | datetime2 |
| Booking | varchar(50) |
| Appointment_Reason | varchar(50) |
| Is_Cancelled | bit |
| Is_DNA | bit |
| Is_Completed | bit |
| Mode | varchar(16) |
| Delay | varchar(19) |
| Next Appointment | varchar(50) |
| Current State | varchar(18) |

### `Gold.vw_Fact_Invoice_Items`

| Column | Type |
|---|---|
| pk_Invoice_Item | bigint |
| Tenant_ID | int |
| bk_Invoice_Item_ID | varchar(255) |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Payment_Plan | bigint |
| fk_Treatment_Plan | bigint |
| fk_Account | bigint |
| fk_Practice_Site | bigint |
| fk_User | bigint |
| fk_Date_Invoice | bigint |
| fk_Date_Due | bigint |
| fk_Date_Paid | bigint |
| fk_Date_Created | bigint |
| Invoice_ID | bigint |
| Treatment_Plan_Item_ID | bigint |
| Sundry_ID | varchar(255) |
| Item_Name | varchar(255) |
| Invoice_Reference | int |
| Invoice_Payment_Terms | varchar(255) |
| Invoice_Footnote | varchar(255) |
| Invoice_Paid | bit |
| Item_Price | decimal |
| Quantity | decimal |
| Total_Price | decimal |
| NHS_Charge | decimal |
| Invoice_Amount | decimal |
| Invoice_Amount_Outstanding | decimal |
| Invoice_NHS_Amount | decimal |
| Is_Invoice_Outstanding | bit |
| Is_Discount | bit |
| Aged_Debt_Band | varchar(11) |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |

### `Gold.vw_Fact_Payments`

| Column | Type |
|---|---|
| pk_Payment | bigint |
| Tenant_ID | int |
| bk_Payment_ID | int |
| fk_Patient | bigint |
| fk_Practitioner | bigint |
| fk_Practice_Site | bigint |
| fk_Date_Payment | bigint |
| Payment_Method | varchar(100) |
| Payment_Amount | decimal |
| Is_Deposit | bit |
| Deposit_Amount | decimal |
| DW_Created_At | datetime2 |
| DW_Updated_At | datetime2 |


