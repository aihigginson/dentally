-- Billing.usp_Generate_Invoice_Lines
-- Run on the 1st of each month (schedule via a Fabric pipeline, or a 1st-of-month guard in
-- Orchestrate_Build). Snapshots the CURRENT access state (= end of the month just ended), applies
-- that month's effective price, and writes Billing.Invoice_Line. Idempotent per month (clears +
-- regenerates the given month), so it is safe to re-run.
--   To run manually: EXEC Billing.usp_Generate_Invoice_Lines @Year_Month = 202701;  -- NULL = last month
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Billing].[usp_Generate_Invoice_Lines]
GO
CREATE PROCEDURE [Billing].[usp_Generate_Invoice_Lines]
(
    @Year_Month INT = NULL   -- YYYYMM to bill; NULL = the month that just ended
)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Year_Month IS NULL
    BEGIN
        DECLARE @prev DATE = DATEADD(month, -1, CAST(SYSUTCDATETIME() AS DATE));
        SET @Year_Month = YEAR(@prev) * 100 + MONTH(@prev);
    END

    -- idempotent: clear this month's lines, then regenerate from the current access snapshot
    DELETE FROM [Billing].[Invoice_Line] WHERE [Year_Month] = @Year_Month;

    ;WITH prof AS (
        SELECT t.Tenant_ID, au.User_UPN, au.Display_Name,
               COALESCE(au.Profile_Key, CASE
                 WHEN au.Access_Home=1 AND au.Access_Revenue=1 AND au.Access_Patient=1 AND au.Access_Schedule=1 AND au.Access_Clinical=1 AND au.Access_NHS=1 AND au.Access_Day_Book=1 AND au.Access_Finance=1 AND au.Access_My_Data=1 AND au.Access_Marketing=1 THEN 'full'
                 WHEN au.Access_Home=1 AND au.Access_Clinical=1 AND au.Access_NHS=1 AND au.Access_Schedule=1 AND au.Access_Patient=1 AND au.Access_My_Data=1 AND au.Access_Revenue=0 AND au.Access_Day_Book=0 AND au.Access_Finance=0 AND au.Access_Marketing=0 THEN 'clinician'
                 WHEN au.Access_Home=1 AND au.Access_Schedule=1 AND au.Access_Patient=1 AND au.Access_Revenue=0 AND au.Access_Clinical=0 AND au.Access_NHS=0 AND au.Access_Day_Book=0 AND au.Access_Finance=0 AND au.Access_My_Data=0 AND au.Access_Marketing=0 THEN 'front_office'
                 ELSE 'no_access' END) AS Profile_Key
        FROM [Security].[Application_Users] au
        JOIN [Audit].[Tenants] t ON t.Client_ID = au.Client_ID
    ),
    price AS (
        SELECT p.Profile_Key, p.Monthly_Price
        FROM [Billing].[Profile_Pricing] p
        JOIN (SELECT Profile_Key, MAX(Year_Month) AS mym
              FROM [Billing].[Profile_Pricing] WHERE Year_Month <= @Year_Month GROUP BY Profile_Key) m
          ON m.Profile_Key = p.Profile_Key AND m.mym = p.Year_Month
    )
    INSERT INTO [Billing].[Invoice_Line] (Tenant_ID, Year_Month, User_UPN, Display_Name, Profile_Key, Value, Generated_At)
    SELECT prof.Tenant_ID, @Year_Month, prof.User_UPN, prof.Display_Name, prof.Profile_Key, pr.Monthly_Price, SYSUTCDATETIME()
    FROM prof
    JOIN price pr ON pr.Profile_Key = prof.Profile_Key
    WHERE prof.Profile_Key <> 'no_access' AND pr.Monthly_Price > 0;
END
GO
