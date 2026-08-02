--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_NHS_Contracts] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_NHS_Contracts
--  Author           :  AIH
--  Initital Date    :  03/06/2026
--  History          :
--    *01     03/06/2026  AIH Initial Release
--  To Run           :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Dim_NHS_Contracts @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_NHS_Contracts]    Script Date: 03/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_NHS_Contracts]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_NHS_Contracts]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
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
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        SELECT
            c.Tenant_ID,
            NULLIF(TRIM(c.Id), '')                  AS bk_Contract_ID,
            NULLIF(TRIM(c.Contract_Number), '')      AS Contract_Number,
            NULLIF(TRIM(c.Name), '')                 AS Contract_Name,
            NULLIF(TRIM(c.Site_ID), '')              AS Site_ID,
            c.Active,
            c.PDS_Plus,
            NULLIF(TRIM(c.NHS_Location_ID), '')      AS NHS_Location_ID,
            NULLIF(TRIM(c.NHS_Site_ID), '')          AS NHS_Site_ID,
            c.Start_Date,
            c.End_Date,
            c.Target                                 AS UDA_Target,
            c.UDA_Value,
            c.UOA_Target,
            c.UOA_Value,
            CAST(0 AS BIT)                           AS Is_Rolled_Forward
        INTO #src
        FROM Silver.Contracts c
        WHERE c.Id IS NOT NULL;

        -- Roll-forward (V145): NHS contracts often lag the source. For each site with a real contract,
        -- if a later Apr-Mar year has NHS claims (submissions) but NO contract, synthesize one from that
        -- site's LATEST real contract, dated to the missing year and flagged Is_Rolled_Forward = 1 (never
        -- mistaken for a real source row). Built into #src so the MERGE persists it and auto-removes it
        -- once a real contract supersedes it; deterministic bk_Contract_ID (RF-<orig>-<FY>) = idempotent.
        DECLARE @Current_NHS_Year INT =
            (SELECT MAX(Financial_Year) FROM Gold.Dim_Date WHERE Full_Date <= CAST(SYSUTCDATETIME() AS DATE));

        ;WITH latest AS (
            SELECT s.Tenant_ID, s.Site_ID, s.bk_Contract_ID, s.Contract_Number, s.Contract_Name,
                   s.Active, s.PDS_Plus, s.NHS_Location_ID, s.NHS_Site_ID,
                   s.UDA_Target, s.UDA_Value, s.UOA_Target, s.UOA_Value, s.End_Date,
                   ROW_NUMBER() OVER (PARTITION BY s.Tenant_ID, s.Site_ID ORDER BY s.End_Date DESC) AS rn
            FROM   #src s
            WHERE  s.End_Date IS NOT NULL AND ISNULL(s.UDA_Target, 0) > 0
        ),
        ny AS (
            SELECT Financial_Year, MIN(Full_Date) AS FY_Start, MAX(Full_Date) AS FY_End
            FROM   Gold.Dim_Date GROUP BY Financial_Year
        ),
        claim_yr AS (
            -- V146: source submission years from Silver (loaded before ALL Gold) instead of
            -- Gold.Fact_NHS_Claims. A GOLD_DIM must not read a Gold FACT (ordered after it) --
            -- on a fresh build the fact is empty when this Dim runs, so the roll-forward would
            -- silently miss years. Silver.NHS_Claims carries the same submission dates + Site_ID.
            SELECT DISTINCT cl.Tenant_ID, cl.Site_ID, d.Financial_Year
            FROM   Silver.NHS_Claims cl
            JOIN   Gold.Dim_Date d ON d.Full_Date = cl.Submitted_Date
            WHERE  cl.Submitted_Date IS NOT NULL
        ),
        covered AS (
            SELECT DISTINCT s.Tenant_ID, s.Site_ID, d.Financial_Year
            FROM   #src s
            JOIN   Gold.Dim_Date d ON d.Full_Date BETWEEN s.Start_Date AND s.End_Date
            WHERE  s.Start_Date IS NOT NULL AND s.End_Date IS NOT NULL
        )
        SELECT
            l.Tenant_ID,
            'RF-' + l.bk_Contract_ID + '-' + CAST(ny.Financial_Year AS VARCHAR(10)) AS bk_Contract_ID,
            l.Contract_Number,
            LEFT(ISNULL(l.Contract_Name, 'NHS Contract') + ' (rolled forward)', 255) AS Contract_Name,
            l.Site_ID, l.Active, l.PDS_Plus, l.NHS_Location_ID, l.NHS_Site_ID,
            ny.FY_Start AS Start_Date, ny.FY_End AS End_Date,
            l.UDA_Target, l.UDA_Value, l.UOA_Target, l.UOA_Value,
            CAST(1 AS BIT) AS Is_Rolled_Forward
        INTO   #rollfwd
        FROM   latest l
        JOIN   claim_yr cy ON cy.Tenant_ID = l.Tenant_ID AND cy.Site_ID = l.Site_ID
        JOIN   ny          ON ny.Financial_Year = cy.Financial_Year
        WHERE  l.rn = 1
          AND  ny.FY_Start > l.End_Date
          AND  ny.Financial_Year <= @Current_NHS_Year
          AND  NOT EXISTS (SELECT 1 FROM covered cv
                           WHERE cv.Tenant_ID = l.Tenant_ID AND cv.Site_ID = l.Site_ID
                             AND cv.Financial_Year = ny.Financial_Year);

        INSERT INTO #src (Tenant_ID, bk_Contract_ID, Contract_Number, Contract_Name, Site_ID, Active,
                          PDS_Plus, NHS_Location_ID, NHS_Site_ID, Start_Date, End_Date,
                          UDA_Target, UDA_Value, UOA_Target, UOA_Value, Is_Rolled_Forward)
        SELECT Tenant_ID, bk_Contract_ID, Contract_Number, Contract_Name, Site_ID, Active,
               PDS_Plus, NHS_Location_ID, NHS_Site_ID, Start_Date, End_Date,
               UDA_Target, UDA_Value, UOA_Target, UOA_Value, Is_Rolled_Forward
        FROM   #rollfwd;

        DROP TABLE #rollfwd;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_NHS_Contracts tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_Contract_ID = tgt.bk_Contract_ID AND Tenant_ID = tgt.Tenant_ID)
          AND tgt.pk_NHS_Contract <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Contract_Number     = src.Contract_Number,
            Contract_Name       = src.Contract_Name,
            Site_ID             = src.Site_ID,
            Active              = src.Active,
            PDS_Plus            = src.PDS_Plus,
            NHS_Location_ID     = src.NHS_Location_ID,
            NHS_Site_ID         = src.NHS_Site_ID,
            Start_Date          = src.Start_Date,
            End_Date            = src.End_Date,
            UDA_Target          = src.UDA_Target,
            UDA_Value           = src.UDA_Value,
            UOA_Target          = src.UOA_Target,
            UOA_Value           = src.UOA_Value,
            Is_Rolled_Forward   = src.Is_Rolled_Forward,
            DW_Updated_At       = SYSUTCDATETIME()
        FROM Gold.Dim_NHS_Contracts tgt
        INNER JOIN #src src ON tgt.bk_Contract_ID = src.bk_Contract_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Contract_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Contract_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[PDS_Plus] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Location_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UOA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UOA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Is_Rolled_Forward] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Contract_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Contract_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[PDS_Plus] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Location_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UOA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UOA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Is_Rolled_Forward] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_NHS_Contract_base BIGINT = ISNULL((SELECT MAX(pk_NHS_Contract) FROM Gold.Dim_NHS_Contracts WHERE pk_NHS_Contract > 0), 0);

        INSERT INTO Gold.Dim_NHS_Contracts (
            pk_NHS_Contract, Tenant_ID, bk_Contract_ID,
            Contract_Number, Contract_Name, Site_ID, Active, PDS_Plus,
            NHS_Location_ID, NHS_Site_ID, Start_Date, End_Date,
            UDA_Target, UDA_Value, UOA_Target, UOA_Value, Is_Rolled_Forward,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_NHS_Contract_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.bk_Contract_ID),
            src.Tenant_ID, src.bk_Contract_ID,
            src.Contract_Number, src.Contract_Name, src.Site_ID, src.Active, src.PDS_Plus,
            src.NHS_Location_ID, src.NHS_Site_ID, src.Start_Date, src.End_Date,
            src.UDA_Target, src.UDA_Value, src.UOA_Target, src.UOA_Value, ISNULL(src.Is_Rolled_Forward, CAST(0 AS BIT)),
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_NHS_Contracts tgt WHERE tgt.bk_Contract_ID = src.bk_Contract_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 sentinel row exists
        INSERT INTO Gold.Dim_NHS_Contracts (pk_NHS_Contract, Tenant_ID, bk_Contract_ID, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, '-1', SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_NHS_Contracts WHERE pk_NHS_Contract = -1);

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes

END
GO
