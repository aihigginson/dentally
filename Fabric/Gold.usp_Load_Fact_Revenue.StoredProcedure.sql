-- DECLARE @i BIGINT=0,@u BIGINT=0,@d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Revenue] @Mode='PROD', @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
---------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Revenue
--  Author           :  AIH
--  Initial Date     :  2026-08-10
--  History          :
--    *01     2026-08-10  AIH  Initial: unified revenue-line fact = invoice lines + capitation.
--                             STAGE 1 -- sources the two existing Gold facts (Fact_Invoice_Items +
--                             Fact_Plan_Capitation) so it is GOLD_AGG for now; proves shape +
--                             category + reconciliation. STAGE 2 (later) re-sources both halves
--                             from Silver -> GOLD_FACT and retires the two source facts.
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

        -- ---- Invoice lines ---------------------------------------------------------------------
        -- Category: sundry lines -> 'Sundries'; else the treatment's Standard Treatment Category
        -- (unmapped -> 'Other'). fk_Invoice = -1 covers transient orphans (mid-day ingest lag).
        INSERT INTO [Gold].[Fact_Revenue]
            (Tenant_ID, Revenue_Type, Revenue_Category, fk_Invoice, fk_Patient, fk_Practitioner,
             fk_Practice_Site, fk_Payment_Plan, fk_Treatment, fk_Date, Amount, NHS_Charge,
             Is_Estimated_Plan, bk_Invoice_Item_ID, Item_Name, Item_Price, Quantity, DW_Created_At)
        SELECT
              ii.Tenant_ID, 'Invoice',
              CASE WHEN NULLIF(LTRIM(RTRIM(ii.Sundry_ID)),'') IS NOT NULL THEN 'Sundries'
                   ELSE COALESCE(dt.Standard_Treatment_Category, 'Other') END,
              ISNULL(ii.fk_Invoice,-1), ISNULL(ii.fk_Patient,-1), ISNULL(ii.fk_Practitioner,-1),
              ISNULL(ii.fk_Practice_Site,-1), ISNULL(ii.fk_Payment_Plan,-1), ISNULL(ii.fk_Treatment,-1), ISNULL(ii.fk_Date_Invoice,-1),
              ISNULL(CAST(ii.Total_Price AS DECIMAL(18,6)),0), ii.NHS_Charge,
              0, ii.bk_Invoice_Item_ID, ii.Item_Name,
              CAST(ii.Item_Price AS DECIMAL(18,4)), CAST(ii.Quantity AS DECIMAL(18,4)), SYSUTCDATETIME()
        FROM [Gold].[Fact_Invoice_Items] ii
        LEFT JOIN [Gold].[Dim_Treatments] dt
               ON dt.pk_Treatment = ii.fk_Treatment AND dt.Tenant_ID = ii.Tenant_ID;
        SET @My_Inserts = @@ROWCOUNT;

        -- ---- Capitation member-days ------------------------------------------------------------
        -- Daily pro-rata membership revenue (already daily post-V147). No treatment / no invoice.
        INSERT INTO [Gold].[Fact_Revenue]
            (Tenant_ID, Revenue_Type, Revenue_Category, fk_Invoice, fk_Patient, fk_Practitioner,
             fk_Practice_Site, fk_Payment_Plan, fk_Treatment, fk_Date, Amount, NHS_Charge,
             Is_Estimated_Plan, bk_Invoice_Item_ID, Item_Name, Item_Price, Quantity, DW_Created_At)
        SELECT
              pc.Tenant_ID, 'Capitation', 'Plan Capitation',
              -1, pc.fk_Patient, pc.fk_Practitioner,
              pc.fk_Practice_Site, pc.fk_Payment_Plan, -1, pc.fk_Date,
              CAST(pc.Daily_Value AS DECIMAL(18,6)), 0,
              pc.Is_Estimated_Plan, NULL, NULL, NULL, NULL, SYSUTCDATETIME()
        FROM [Gold].[Fact_Plan_Capitation] pc;
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
