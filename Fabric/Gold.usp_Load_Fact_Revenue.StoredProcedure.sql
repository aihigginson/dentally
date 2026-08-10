-- DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Revenue] @Mode='PROD', @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
---------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Revenue
--  Author           :  AIH
--  Initial Date     :  2026-08-10
--  History          :
--    *01     2026-08-10  AIH  Stage 1: union of Gold facts (Fact_Invoice_Items + Fact_Plan_Capitation).
--    *02     2026-08-10  AIH  Stage 2: re-source BOTH halves from Silver -> GOLD_FACT (no Gold-fact
--                             reads). Invoice half = the proven Fact_Invoice_Items resolution (full
--                             pull). Capitation half = the V147 pro-rata logic with plan_course
--                             re-sourced from Silver.Treatment_Plans/Items (pk_Patient resolved up
--                             front; everything downstream identical). Retires Fact_Invoice_Items +
--                             Fact_Plan_Capitation. Output must reconcile to Stage 1 to the penny.
--    *03     2026-08-10  AIH  Capitation: WORKING days only (fee/working-days-in-month) and only from
--                             Audit.Tenants.Cutover_Date (per-tenant Dentally go-live) -- drops the pre-
--                             go-live phantom capitation (imported historical plans back to 2010).
--  Purpose          :  One row per revenue unit (invoice line OR capitation member-day). Revenue is
--                      defined once here so header/line/category totals cannot diverge. Full rebuild.
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Gold.usp_Load_Fact_Revenue
--                      @Mode='PROD', @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Revenue]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Revenue]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       SMALLINT         = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        DECLARE @Current_Month DATE = DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1);

        DROP TABLE IF EXISTS [Gold].[Fact_Revenue];

        CREATE TABLE [Gold].[Fact_Revenue] (
              [pk_Revenue]          BIGINT IDENTITY   NOT NULL,
              [Tenant_ID]           INT               NOT NULL,
              [Revenue_Type]        VARCHAR(20)       NOT NULL,
              [Revenue_Category]    VARCHAR(100)      NOT NULL,
              [fk_Invoice]          BIGINT            NOT NULL,
              [fk_Patient]          BIGINT            NOT NULL,
              [fk_Practitioner]     BIGINT            NOT NULL,
              [fk_Practice_Site]    BIGINT            NOT NULL,
              [fk_Payment_Plan]     BIGINT            NOT NULL,
              [fk_Treatment]        BIGINT            NOT NULL,
              [fk_Date]             BIGINT            NOT NULL,
              [Amount]              DECIMAL(18,6)     NOT NULL,
              [NHS_Charge]          DECIMAL(12,2)     NULL,
              [Is_Estimated_Plan]   BIT               NOT NULL,
              [bk_Invoice_Item_ID]  VARCHAR(100)      NULL,
              [Item_Name]           VARCHAR(255)      NULL,
              [Item_Price]          DECIMAL(18,4)     NULL,
              [Quantity]            DECIMAL(18,4)     NULL,
              [DW_Created_At]       DATETIME2(3)      NOT NULL
        );

        -- ===== Invoice lines (Silver.Invoice_Items -- proven Fact_Invoice_Items resolution) =====
        INSERT INTO [Gold].[Fact_Revenue]
            (Tenant_ID, Revenue_Type, Revenue_Category, fk_Invoice, fk_Patient, fk_Practitioner,
             fk_Practice_Site, fk_Payment_Plan, fk_Treatment, fk_Date, Amount, NHS_Charge,
             Is_Estimated_Plan, bk_Invoice_Item_ID, Item_Name, Item_Price, Quantity, DW_Created_At)
        SELECT
              ii.Tenant_ID, 'Invoice',
              CASE WHEN NULLIF(LTRIM(RTRIM(ii.Sundry_ID)),'') IS NOT NULL THEN 'Sundries'
                   ELSE COALESCE(dt.Standard_Treatment_Category, 'Other') END,
              ISNULL(dinv.pk_Invoice, -1), ISNULL(dpat.pk_Patient, -1), ISNULL(dpr.pk_Practitioner, -1),
              ISNULL(dps.pk_Practice_Site, -1), ISNULL(dpp.pk_Payment_Plan, -1), ISNULL(dt.pk_Treatment, -1),
              ISNULL(dd_inv.pk_Date, -1),
              CAST(ISNULL(ii.Total_Price,0) AS DECIMAL(18,6)), CAST(ISNULL(ii.NHS_Charge,0) AS DECIMAL(12,2)),
              0, CAST(ii.Id AS VARCHAR(100)), NULLIF(LTRIM(RTRIM(ii.Name)),''),
              CAST(ISNULL(ii.Item_Price,0) AS DECIMAL(18,4)), CAST(ISNULL(ii.Quantity,0) AS DECIMAL(18,4)), SYSUTCDATETIME()
        FROM [Silver].[Invoice_Items] ii
        LEFT JOIN [Silver].[Invoices] inv        ON inv.Id = ii.Invoice_ID AND inv.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Invoices] dinv     ON dinv.bk_Invoice_ID = TRY_CAST(ii.Invoice_ID AS INT) AND dinv.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Patients] dpat     ON dpat.Patient_ID = TRY_CAST(inv.Patient_ID AS INT) AND dpat.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Practitioners] dpr ON dpr.Practitioner_ID = TRY_CAST(ii.Practitioner_ID AS INT) AND dpr.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Payment_Plans] dpp ON dpp.Payment_Plan_ID = (
                                                      SELECT TOP 1 Payment_Plan_ID FROM [Silver].[Patients]
                                                      WHERE Patient_ID = TRY_CAST(inv.Patient_ID AS INT) AND Tenant_ID = ii.Tenant_ID)
                                                    AND dpp.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Silver].[Treatment_Plan_Items] tpi ON tpi.Id = ii.Treatment_Plan_Item_ID AND tpi.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Treatments] dt     ON dt.Treatment_ID = tpi.Treatment_ID AND dt.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps ON dps.Site_ID = NULLIF(LTRIM(RTRIM(inv.Site_ID)),'') AND dps.Tenant_ID = ii.Tenant_ID
        LEFT JOIN [Gold].[Dim_Date] dd_inv       ON dd_inv.Full_Date = TRY_CAST(inv.Dated_On AS DATE)
        WHERE ii.Id IS NOT NULL;
        SET @My_Inserts = @@ROWCOUNT;

        -- ===== Capitation member-days (Silver.Treatment_Plans/Items -- V147 pro-rata) ===========
        ;WITH plan_course AS (
            -- membership-evidence months: completed, non-NHS, non-charged Exam/Hygiene courses.
            -- Re-sourced from Silver: resolve pk_Patient up front so the rest of the pipeline is
            -- byte-identical to V147; course_month straight from Start_Date (no Dim_Date surrogate).
            SELECT tp.Tenant_ID, dp.pk_Patient AS fk_Patient,
                   DATEFROMPARTS(YEAR(tp.Start_Date), MONTH(tp.Start_Date), 1) AS course_month
            FROM   [Silver].[Treatment_Plans] tp
            JOIN   [Gold].[Dim_Patients] dp ON dp.Patient_ID = tp.Patient_ID AND dp.Tenant_ID = tp.Tenant_ID
            WHERE  tp.Completed = 1
              AND  tp.Start_Date IS NOT NULL
              AND  ISNULL(TRY_CAST(tp.NHS_UDA_Value AS DECIMAL(18,4)), 0)           = 0
              AND  ISNULL(TRY_CAST(tp.Private_Treatment_Value AS DECIMAL(18,4)), 0) = 0
              AND  EXISTS (SELECT 1 FROM [Silver].[Treatment_Plan_Items] i
                           WHERE TRY_CAST(i.Treatment_Plan_ID AS BIGINT) = TRY_CAST(tp.Id AS BIGINT) AND i.Tenant_ID = tp.Tenant_ID
                             AND i.Nomenclature IN ('Exam','Hygiene 20','Hygiene 30','Routine Hygiene')
                             AND i.Charged = 0)
        ),
        tenure AS (
            SELECT Tenant_ID, fk_Patient,
                   MIN(course_month)            AS start_m,
                   MAX(course_month)            AS last_m,
                   COUNT(DISTINCT course_month) AS course_months
            FROM   plan_course GROUP BY Tenant_ID, fk_Patient
        ),
        rated_plans AS (
            SELECT DISTINCT Tenant_ID, Payment_Plan_ID FROM [Input].[Plan_Capitation_Rate]
        ),
        default_plan AS (
            SELECT DISTINCT Tenant_ID, Payment_Plan_ID FROM [Input].[Plan_Capitation_Rate] WHERE Is_Default = 1
        ),
        resolved AS (
            SELECT t.Tenant_ID, t.fk_Patient, t.start_m, t.course_months,
                   COALESCE(own.Payment_Plan_ID, def.Payment_Plan_ID) AS attributed_plan_id,
                   CASE WHEN own.Payment_Plan_ID IS NOT NULL THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS is_estimated,
                   CASE WHEN own.Payment_Plan_ID IS NOT NULL AND pat.Active = 1
                        THEN @Current_Month ELSE t.last_m END AS end_m
            FROM   tenure t
            JOIN   [Gold].[Dim_Patients] pat ON pat.pk_Patient = t.fk_Patient
            LEFT JOIN rated_plans  own ON own.Tenant_ID = t.Tenant_ID AND own.Payment_Plan_ID = pat.Payment_Plan_ID
            LEFT JOIN default_plan def ON def.Tenant_ID = t.Tenant_ID
            WHERE  COALESCE(own.Payment_Plan_ID, def.Payment_Plan_ID) IS NOT NULL
              AND  (own.Payment_Plan_ID IS NOT NULL OR t.course_months >= 2)
        ),
        months AS (
            SELECT r.Tenant_ID, r.fk_Patient, r.attributed_plan_id, r.is_estimated,
                   d.pk_Date, d.Month_Commencing_Date
            FROM   resolved r
            JOIN   [Gold].[Dim_Date] d ON d.Day_Of_Month = 1 AND d.Month_Commencing_Date BETWEEN r.start_m AND r.end_m
        ),
        priced AS (
            SELECT m.Tenant_ID, m.fk_Patient, m.attributed_plan_id, m.is_estimated, m.pk_Date, m.Month_Commencing_Date,
                   rr.Monthly_Value,
                   ROW_NUMBER() OVER (PARTITION BY m.Tenant_ID, m.fk_Patient, m.pk_Date
                                      ORDER BY rr.Effective_From_Date DESC) AS rn
            FROM   months m
            JOIN   [Input].[Plan_Capitation_Rate] rr
                   ON rr.Tenant_ID = m.Tenant_ID AND rr.Payment_Plan_ID = m.attributed_plan_id
                  AND rr.Effective_From_Date <= m.Month_Commencing_Date
        ),
        wdays AS (   -- working days per calendar month (England) -- capitation spreads across these only
            SELECT Month_Commencing_Date, COUNT(*) AS wd
            FROM   [Gold].[Dim_Date] WHERE Is_Working_Day_England = 1
            GROUP BY Month_Commencing_Date
        )
        INSERT INTO [Gold].[Fact_Revenue]
            (Tenant_ID, Revenue_Type, Revenue_Category, fk_Invoice, fk_Patient, fk_Practitioner,
             fk_Practice_Site, fk_Payment_Plan, fk_Treatment, fk_Date, Amount, NHS_Charge,
             Is_Estimated_Plan, bk_Invoice_Item_ID, Item_Name, Item_Price, Quantity, DW_Created_At)
        SELECT p.Tenant_ID, 'Capitation', 'Plan Capitation',
               -1, p.fk_Patient, ISNULL(dpr.pk_Practitioner, -1),
               ISNULL(dps.pk_Practice_Site, -1), ISNULL(dpp.pk_Payment_Plan, -1), -1,
               dday.pk_Date, p.Monthly_Value / wd.wd, 0,
               p.is_estimated, NULL, NULL, NULL, NULL, SYSUTCDATETIME()
        FROM   priced p
        JOIN   [Gold].[Dim_Patients] pat ON pat.pk_Patient = p.fk_Patient
        LEFT JOIN [Gold].[Dim_Payment_Plans]  dpp ON dpp.Tenant_ID = p.Tenant_ID AND dpp.Payment_Plan_ID = p.attributed_plan_id
        LEFT JOIN [Gold].[Dim_Practitioners]  dpr ON dpr.Tenant_ID = p.Tenant_ID AND dpr.Practitioner_ID = pat.Dentist_Practitioner_ID
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps ON dps.Tenant_ID = p.Tenant_ID AND dps.Site_ID = pat.Site_ID
        JOIN      wdays wd ON wd.Month_Commencing_Date = p.Month_Commencing_Date
        JOIN      [Audit].[Tenants] tn ON tn.Tenant_ID = p.Tenant_ID
        JOIN      [Gold].[Dim_Date] dday ON dday.Month_Commencing_Date = p.Month_Commencing_Date
                                        AND dday.Is_Working_Day_England = 1
        WHERE  p.rn = 1
          AND  dday.Full_Date <= CAST(SYSUTCDATETIME() AS DATE)
          AND  dday.Full_Date >= tn.Cutover_Date;   -- from the tenant's Dentally go-live only
        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
