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
--    *04     2026-09-27  AIH  Capitation regrained from MEMBER-DAY to WEEK-WITHIN-MONTH segment:
--                             one row per full week inside a month, split where a week crosses a
--                             month boundary. 2,613,357 rows -> 588,854 (4.4x) with weekly AND
--                             monthly reporting unchanged, because a segment spans neither
--                             boundary. Same arithmetic regrouped, so it reconciles to the penny.
--                             Also writes Gold.Fact_Plan_Spell from the same pass.
--  Purpose          :  One row per revenue unit (invoice line OR capitation week-within-month
--                      segment). Also rebuilds Gold.Fact_Plan_Spell. Revenue is
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

        -- ===== Capitation: continuous plan spells, expanded to WEEK-within-MONTH segments ====
        -- ==> THIS USED TO BE ONE ROW PER MEMBER PER WORKING DAY. IT IS NOW ONE PER SEGMENT. <==
        --
        -- 2,613,357 rows for 2,732 members, at about 1.70 each -- the overwhelming majority of
        -- Fact_Revenue, to express a handful of monthly fees. The day grain existed for one
        -- honest reason: some revenue reports are WEEKLY and some MONTHLY, and a monthly row
        -- cannot answer a weekly question.
        --
        -- A segment is a week clipped to its month. Full weeks inside a month give one row each;
        -- a week crossing a month boundary gives two, one for each side. So a segment never
        -- spans a week boundary and never spans a month boundary, which means BOTH the weekly
        -- and the monthly reports still sum exactly, with 4.4x fewer rows (2,613,357 -> 588,854).
        -- Month-only storage would be 21.7x fewer and is the obvious temptation, but it cannot
        -- serve the weekly reports, which is precisely why the day grain was there.
        --
        -- April 2026 is 1 Apr (part week), then 6, 13, 20, 27. Weeks are MONDAY-commencing
        -- because that is what Gold.Dim_Date says -- Week_Commencing_Date, not an invented
        -- boundary. Anything else and the weekly reports would silently disagree with every
        -- other weekly figure in the warehouse.
        --
        -- ==> THE ARITHMETIC IS THE OLD ARITHMETIC, REGROUPED, SO IT RECONCILES TO THE PENNY. <==
        -- Each day was Monthly_Value / working_days_in_month. A segment is that same daily rate
        -- times the working days in the segment. Amount is DECIMAL(18,6), so the sum over
        -- segments equals the sum over days exactly, not approximately. The release guard
        -- asserts it rather than trusting it.
        --
        -- The part month needs no special case, which is the point of counting working days
        -- rather than dividing weeks. Days are filtered to <= today before they are counted, so
        -- the current segment carries only the days actually elapsed and the current month
        -- accrues exactly as it did at day grain -- a Monday does not book the whole week.
        ;WITH plan_course AS (
            -- membership-evidence months: completed, non-NHS, non-charged Exam/Hygiene courses.
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
            -- First to last evidence month. Gaps are bridged deliberately: missing an exam does
            -- not cancel a membership, so this is ONE spell per patient, not one per unbroken
            -- run. Evidence_Months on the spell table keeps the gaps visible rather than hidden.
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
        )
        -- Materialised, not left as a CTE: the spell is written to Gold.Fact_Plan_Spell further
        -- down, and computing it twice is how a stored spell and the revenue derived from it
        -- drift apart.
        SELECT t.Tenant_ID, t.fk_Patient, t.start_m, t.course_months,
               COALESCE(own.Payment_Plan_ID, def.Payment_Plan_ID) AS attributed_plan_id,
               CASE WHEN own.Payment_Plan_ID IS NOT NULL THEN CAST(0 AS BIT) ELSE CAST(1 AS BIT) END AS is_estimated,
               CASE WHEN own.Payment_Plan_ID IS NOT NULL AND pat.Active = 1
                    THEN @Current_Month ELSE t.last_m END AS end_m,
               pat.Dentist_Practitioner_ID, pat.Site_ID
        INTO   #spell
        FROM   tenure t
        JOIN   [Gold].[Dim_Patients] pat ON pat.pk_Patient = t.fk_Patient
        LEFT JOIN rated_plans  own ON own.Tenant_ID = t.Tenant_ID AND own.Payment_Plan_ID = pat.Payment_Plan_ID
        LEFT JOIN default_plan def ON def.Tenant_ID = t.Tenant_ID
        WHERE  COALESCE(own.Payment_Plan_ID, def.Payment_Plan_ID) IS NOT NULL
          AND  (own.Payment_Plan_ID IS NOT NULL OR t.course_months >= 2);

        ;WITH months AS (
            SELECT r.Tenant_ID, r.fk_Patient, r.attributed_plan_id, r.is_estimated,
                   r.Dentist_Practitioner_ID, r.Site_ID, d.Month_Commencing_Date
            FROM   #spell r
            JOIN   [Gold].[Dim_Date] d ON d.Day_Of_Month = 1
                                      AND d.Month_Commencing_Date BETWEEN r.start_m AND r.end_m
        ),
        priced AS (
            -- Latest rate effective on or before the month wins. Unchanged.
            SELECT m.Tenant_ID, m.fk_Patient, m.attributed_plan_id, m.is_estimated,
                   m.Dentist_Practitioner_ID, m.Site_ID, m.Month_Commencing_Date, rr.Monthly_Value,
                   ROW_NUMBER() OVER (PARTITION BY m.Tenant_ID, m.fk_Patient, m.Month_Commencing_Date
                                      ORDER BY rr.Effective_From_Date DESC) AS rn
            FROM   months m
            JOIN   [Input].[Plan_Capitation_Rate] rr
                   ON rr.Tenant_ID = m.Tenant_ID AND rr.Payment_Plan_ID = m.attributed_plan_id
                  AND rr.Effective_From_Date <= m.Month_Commencing_Date
        ),
        wdays AS (   -- working days per calendar month (England) -- the denominator, unbounded
            SELECT Month_Commencing_Date, COUNT(*) AS wd
            FROM   [Gold].[Dim_Date] WHERE Is_Working_Day_England = 1
            GROUP BY Month_Commencing_Date
        ),
        seg AS (
            -- The numerator: working days in this week-within-month that are actually billable.
            -- Clipping the week to the month start is what splits a boundary-crossing week in two.
            SELECT p.Tenant_ID, p.fk_Patient, p.attributed_plan_id, p.is_estimated,
                   p.Dentist_Practitioner_ID, p.Site_ID,
                   p.Month_Commencing_Date, p.Monthly_Value,
                   CASE WHEN d.Week_Commencing_Date < p.Month_Commencing_Date
                        THEN p.Month_Commencing_Date ELSE d.Week_Commencing_Date END AS seg_start,
                   COUNT(*) AS wd_seg
            FROM   priced p
            JOIN   [Audit].[Tenants] tn ON tn.Tenant_ID = p.Tenant_ID
            JOIN   [Gold].[Dim_Date] d
                   ON d.Month_Commencing_Date = p.Month_Commencing_Date
                  AND d.Is_Working_Day_England = 1
                  AND d.Full_Date <= CAST(SYSUTCDATETIME() AS DATE)
                  AND d.Full_Date >= tn.Cutover_Date   -- from the tenant's Dentally go-live only
            WHERE  p.rn = 1
            GROUP BY p.Tenant_ID, p.fk_Patient, p.attributed_plan_id, p.is_estimated,
                     p.Dentist_Practitioner_ID, p.Site_ID,
                     p.Month_Commencing_Date, p.Monthly_Value,
                     CASE WHEN d.Week_Commencing_Date < p.Month_Commencing_Date
                          THEN p.Month_Commencing_Date ELSE d.Week_Commencing_Date END
        )
        INSERT INTO [Gold].[Fact_Revenue]
            (Tenant_ID, Revenue_Type, Revenue_Category, fk_Invoice, fk_Patient, fk_Practitioner,
             fk_Practice_Site, fk_Payment_Plan, fk_Treatment, fk_Date, Amount, NHS_Charge,
             Is_Estimated_Plan, bk_Invoice_Item_ID, Item_Name, Item_Price, Quantity, DW_Created_At)
        SELECT s.Tenant_ID, 'Capitation', 'Plan Capitation',
               -1, s.fk_Patient, ISNULL(dpr.pk_Practitioner, -1),
               ISNULL(dps.pk_Practice_Site, -1), ISNULL(dpp.pk_Payment_Plan, -1), -1,
               dseg.pk_Date,
               s.Monthly_Value / wd.wd * s.wd_seg,
               0, s.is_estimated, NULL, NULL, NULL, NULL, SYSUTCDATETIME()
        FROM   seg s
        LEFT JOIN [Gold].[Dim_Payment_Plans]  dpp ON dpp.Tenant_ID = s.Tenant_ID AND dpp.Payment_Plan_ID = s.attributed_plan_id
        LEFT JOIN [Gold].[Dim_Practitioners]  dpr ON dpr.Tenant_ID = s.Tenant_ID AND dpr.Practitioner_ID = s.Dentist_Practitioner_ID
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps ON dps.Tenant_ID = s.Tenant_ID AND dps.Site_ID = s.Site_ID
        JOIN      wdays wd  ON wd.Month_Commencing_Date = s.Month_Commencing_Date
        JOIN      [Gold].[Dim_Date] dseg ON dseg.Full_Date = s.seg_start;
        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;

        -- ===== The spell itself, stored once ==================================================
        -- Built from the same #spell that produced the rows above, so the two cannot disagree.
        -- Billed_* is read back off Fact_Revenue because the billable window is NARROWER than the
        -- spell: Cutover_Date clips the front, today clips the back. A patient can be a member
        -- for years before the first penny is attributable, and both facts matter.
        DROP TABLE IF EXISTS [Gold].[Fact_Plan_Spell];
        CREATE TABLE [Gold].[Fact_Plan_Spell] (
              [pk_Plan_Spell]       BIGINT          NOT NULL,
              [Tenant_ID]           INT             NOT NULL,
              [fk_Patient]          BIGINT          NOT NULL,
              [fk_Payment_Plan]     BIGINT          NOT NULL,
              [fk_Practitioner]     BIGINT          NOT NULL,
              [fk_Practice_Site]    BIGINT          NOT NULL,
              [Spell_Start_Date]    DATE            NOT NULL,
              [Spell_End_Date]      DATE            NOT NULL,
              [Spell_Months]        INT                 NULL,
              [Evidence_Months]     INT                 NULL,
              [Is_Open]             BIT             NOT NULL,
              [Is_Estimated_Plan]   BIT             NOT NULL,
              [Billed_From_Date]    DATE                NULL,
              [Billed_To_Date]      DATE                NULL,
              [Billed_Segments]     INT                 NULL,
              [Spell_Value]         DECIMAL(18,6)       NULL,
              [DW_Created_At]       DATETIME2(6)    NOT NULL,
              [DW_Updated_At]       DATETIME2(6)    NOT NULL
        );

        INSERT INTO [Gold].[Fact_Plan_Spell]
            (pk_Plan_Spell, Tenant_ID, fk_Patient, fk_Payment_Plan, fk_Practitioner,
             fk_Practice_Site, Spell_Start_Date, Spell_End_Date, Spell_Months, Evidence_Months,
             Is_Open, Is_Estimated_Plan, Billed_From_Date, Billed_To_Date, Billed_Segments,
             Spell_Value, DW_Created_At, DW_Updated_At)
        SELECT ROW_NUMBER() OVER (ORDER BY s.Tenant_ID, s.fk_Patient, s.start_m),
               s.Tenant_ID, s.fk_Patient,
               ISNULL(dpp.pk_Payment_Plan, -1), ISNULL(dpr.pk_Practitioner, -1),
               ISNULL(dps.pk_Practice_Site, -1),
               s.start_m,
               DATEADD(DAY, -1, DATEADD(MONTH, 1, s.end_m)),   -- last day of the closing month
               DATEDIFF(MONTH, s.start_m, s.end_m) + 1,
               s.course_months,
               CASE WHEN s.end_m >= @Current_Month THEN 1 ELSE 0 END,
               s.is_estimated,
               b.billed_from, b.billed_to, ISNULL(b.segments, 0), ISNULL(b.spell_value, 0),
               SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM   #spell s
        LEFT JOIN (
            SELECT r.Tenant_ID, r.fk_Patient,
                   MIN(d.Full_Date) AS billed_from, MAX(d.Full_Date) AS billed_to,
                   COUNT(*) AS segments, SUM(r.Amount) AS spell_value
            FROM   [Gold].[Fact_Revenue] r
            JOIN   [Gold].[Dim_Date] d ON d.pk_Date = r.fk_Date
            WHERE  r.Revenue_Type = 'Capitation'
            GROUP BY r.Tenant_ID, r.fk_Patient
        ) b ON b.Tenant_ID = s.Tenant_ID AND b.fk_Patient = s.fk_Patient
        LEFT JOIN [Gold].[Dim_Payment_Plans]  dpp ON dpp.Tenant_ID = s.Tenant_ID AND dpp.Payment_Plan_ID = s.attributed_plan_id
        LEFT JOIN [Gold].[Dim_Practitioners]  dpr ON dpr.Tenant_ID = s.Tenant_ID AND dpr.Practitioner_ID = s.Dentist_Practitioner_ID
        LEFT JOIN [Gold].[Dim_Practice_Sites] dps ON dps.Tenant_ID = s.Tenant_ID AND dps.Site_ID = s.Site_ID;

        DROP TABLE #spell;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
