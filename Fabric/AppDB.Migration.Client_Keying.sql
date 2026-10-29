/* ============================================================================
   APPDB MIGRATION -- everything the OWNER decides is keyed on the CLIENT.

   ==> RUN THIS AGAINST AppDB-<env>, AS AN ACCOUNT WITH DDL RIGHTS. <== The app's service
   principal has data rights only (not db_owner, not db_ddladmin), so it cannot run this and
   neither can the tooling. Run AppDB-dev first, prove it, then AppDB-prod.

   ==> WHY. <== Input.* was built when a client was a practice, so it is keyed on Tenant_ID
   throughout. It no longer is: a client can hold a group of practices, and the things in here
   are decided ONCE for the client, not once per practice --

       Targets               a group sets its own, at any level of its hierarchy
       Practice_Config       the financial year start is a client's, not a site's
       Roles                 the role groupings are the client's vocabulary
       Metric_Variance       the RAG bands that go with the targets
       Plan_Capitation_Rate  one commercial rate, however many practices sell the plan
       Practitioner_Pay      FTE and associate share
       Practitioner_Role     ditto
       Billing_Contact       who gets the invoice

   ==> TENANT_ID SURVIVES ONLY WHERE IT IDENTIFIES THE THING BEING DESCRIBED. <== A practitioner
   exists as (Tenant_ID, Practitioner_ID) and a payment plan as (Tenant_ID, Payment_Plan_ID), so
   those rows keep their tenant AND gain the owning client. Everything else is a client fact that
   happened to be stored per practice.

   NOTHING IS DROPPED HERE. Tenant_ID stays on every table, the new column is added alongside and
   backfilled, and the app keeps working throughout -- a column nobody reads yet is harmless,
   whereas a dropped one is an outage. Removing the ones that become redundant is a later,
   separate step, once everything reads Client_ID.

   Idempotent: re-running adds nothing and re-backfills only NULLs.
   ============================================================================ */
SET NOCOUNT ON;

/* ---- 1. the column, everywhere it is needed ------------------------------ */
IF COL_LENGTH('Input.Targets','Client_ID')              IS NULL ALTER TABLE Input.Targets              ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Practice_Config','Client_ID')      IS NULL ALTER TABLE Input.Practice_Config      ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Roles','Client_ID')                IS NULL ALTER TABLE Input.Roles                ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Metric_Variance','Client_ID')      IS NULL ALTER TABLE Input.Metric_Variance      ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Plan_Capitation_Rate','Client_ID') IS NULL ALTER TABLE Input.Plan_Capitation_Rate ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Practitioner_Pay','Client_ID')     IS NULL ALTER TABLE Input.Practitioner_Pay     ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Practitioner_Role','Client_ID')    IS NULL ALTER TABLE Input.Practitioner_Role    ADD Client_ID INT NULL;
IF COL_LENGTH('Input.Billing_Contact','Client_ID')      IS NULL ALTER TABLE Input.Billing_Contact      ADD Client_ID INT NULL;

/* ==> THE PLAN'S NAME, SO ONE RATE COVERS EVERY PRACTICE'S COPY OF IT. <== A group selling
   "Private" in four practices has four Payment_Plan_IDs for one commercial rate. The rate
   attaches to the NAME at client level; Payment_Plan_ID stays so an existing row still resolves
   to the plan it was set against, and so the warehouse can still join.

   Left NULL by this script on purpose: AppDB does not hold plan names -- they come from
   Dentally, through the warehouse -- so backfilling it is the app's job, not a migration's.
   A NULL name means "this rate is still per-plan", which is exactly what it is today. */
IF COL_LENGTH('Input.Plan_Capitation_Rate','Plan_Name') IS NULL
    ALTER TABLE Input.Plan_Capitation_Rate ADD Plan_Name VARCHAR(200) NULL;
GO

/* ---- 2. backfill from the tenant -> client map --------------------------- */
/* Input.Client_Tenant is the mapping the hierarchy screen maintains, and every active tenant is
   in it. A tenant that is NOT would leave NULLs here -- which the check at the end surfaces
   rather than leaving to be discovered by a report that quietly shows nothing. */
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Targets t              JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Practice_Config t      JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Roles t                JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Metric_Variance t      JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Plan_Capitation_Rate t JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Practitioner_Pay t     JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Practitioner_Role t    JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
UPDATE t SET t.Client_ID = ct.Client_ID
FROM Input.Billing_Contact t      JOIN Input.Client_Tenant ct ON ct.Tenant_ID = t.Tenant_ID WHERE t.Client_ID IS NULL;
GO

/* ---- 3. prove it, rather than assume it ---------------------------------- */
SELECT 'Targets'              AS tbl, COUNT(*) AS rows_, SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) AS unmapped FROM Input.Targets
UNION ALL SELECT 'Practice_Config',      COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Practice_Config
UNION ALL SELECT 'Roles',                COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Roles
UNION ALL SELECT 'Metric_Variance',      COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Metric_Variance
UNION ALL SELECT 'Plan_Capitation_Rate', COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Plan_Capitation_Rate
UNION ALL SELECT 'Practitioner_Pay',     COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Practitioner_Pay
UNION ALL SELECT 'Practitioner_Role',    COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Practitioner_Role
UNION ALL SELECT 'Billing_Contact',      COUNT(*), SUM(CASE WHEN Client_ID IS NULL THEN 1 ELSE 0 END) FROM Input.Billing_Contact
ORDER BY tbl;
GO
