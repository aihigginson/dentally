---------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Set_Tenant_Cutover
--  Author           :  AIH
--  Initial Date     :  2026-08-10
--  Purpose          :  Sets Audit.Tenants.Cutover_Date = the practice's Dentally go-live, derived as
--                      MIN(Updated_At) of Treatment Plans. Updated_At is stamped by DENTALLY (not by
--                      migrated history, which keeps its original Start_Date/Created_At), so the
--                      earliest Updated_At is when Dentally first touched the tenant = go-live. This
--                      is the single source of truth that drives downstream cutover logic (e.g. plan
--                      capitation only from go-live). Run at ONBOARDING (per new tenant) and safe to
--                      re-run (idempotent). @Tenant_ID = NULL sets all tenants.
--  To Run           :  EXEC Audit.usp_Set_Tenant_Cutover @Tenant_ID = 100;  (or NULL for all)
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Audit].[usp_Set_Tenant_Cutover]
GO
CREATE PROCEDURE [Audit].[usp_Set_Tenant_Cutover]
(
      @Tenant_ID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE t
       SET t.Cutover_Date = src.cutover
    FROM [Audit].[Tenants] t
    JOIN (
        SELECT Tenant_ID, MIN(TRY_CAST(Updated_At AS DATE)) AS cutover
        FROM   [Silver].[Treatment_Plans]
        WHERE  Updated_At IS NOT NULL
        GROUP BY Tenant_ID
    ) src ON src.Tenant_ID = t.Tenant_ID
    WHERE (@Tenant_ID IS NULL OR t.Tenant_ID = @Tenant_ID);
END
GO
