--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Contracts] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Contracts
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Wrap non-date FK lookups with ISNULL(..., -1) for unknown dimension row
--    *03     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS, PDS, UDA, UOA)
--    *04     14/06/2026  AIH Incremental (watermark) delta load. Clean single-source fact
--                            (Silver.Contracts + stable dim pks), so delta == full refresh.
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Fact_Contracts @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Contracts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Contracts]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Contracts]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
    , @Full_Reload   BIT = 0
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

        -- Incremental watermark: process only Silver contracts changed since the
        -- last successful load (DW_Updated_At is hash-gated, so this is an exact
        -- delta). Missing watermark (first run) or @Full_Reload = 1 -> full load.
        DECLARE @Run_Start datetime2(3) = SYSUTCDATETIME();
        DECLARE @Watermark datetime2(3) =
            CASE WHEN @Full_Reload = 1 THEN CONVERT(datetime2(3), '1900-01-01')
                 ELSE ISNULL((SELECT Last_Loaded_At FROM Gold.Load_Watermark
                              WHERE Entity_Name = 'Fact_Contracts'),
                             CONVERT(datetime2(3), '1900-01-01'))
            END;

        SELECT
            c.Tenant_ID                                                 AS Tenant_ID,
            c.Id                                                        AS bk_Contract_ID,
            ISNULL(dps.pk_Practice_Site, -1)                            AS fk_Practice_Site,
            dd_s.pk_Date                                                AS fk_Date_Start,
            dd_e.pk_Date                                                AS fk_Date_End,
            TRY_CAST(c.Contract_Number AS INT)                          AS Contract_Number,
            TRY_CAST(c.NHS_Location_ID AS INT)                         AS NHS_Location_ID,
            TRY_CAST(c.NHS_Site_ID AS INT)                             AS NHS_Site_ID,
            NULLIF(TRIM(c.Site_ID),'')                                  AS Site_ID,
            CAST(ISNULL(c.Active,0) AS BIT)                             AS Active,
            CAST(ISNULL(c.PDS_Plus,0) AS BIT)                           AS PDS_Plus,
            CAST(c.Start_Date AS DATE)                                  AS Start_Date,
            CAST(c.End_Date AS DATE)                                    AS End_Date,
            CAST(ISNULL(c.Target,0) AS DECIMAL(12,2))                   AS UDA_Target,
            CAST(ISNULL(c.UDA_Value,0) AS DECIMAL(12,4))                AS UDA_Value,
            CAST(ISNULL(c.UOA_Target,0) AS DECIMAL(12,2))               AS UOA_Target,
            CAST(ISNULL(c.UOA_Value,0) AS DECIMAL(12,4))                AS UOA_Value
        INTO #src
        FROM Silver.Contracts c
        LEFT JOIN Gold.Dim_Practice_Sites dps ON dps.Site_ID = NULLIF(TRIM(c.Site_ID),'') AND dps.Tenant_ID = c.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_s          ON dd_s.Full_Date = CAST(c.Start_Date AS DATE)
        LEFT JOIN Gold.Dim_Date dd_e          ON dd_e.Full_Date = CAST(c.End_Date AS DATE)
        WHERE c.Id IS NOT NULL
          AND c.DW_Updated_At > @Watermark;   -- delta: only changed/new contracts

        -- Remove rows no longer in source. #src is now a DELTA, so orphan detection
        -- runs against the FULL Silver key set (keys only -- cheap).
        DELETE tgt
        FROM Gold.Fact_Contracts tgt
        WHERE NOT EXISTS (SELECT 1 FROM Silver.Contracts s
                          WHERE s.Id = tgt.bk_Contract_ID AND s.Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Practice_Site = src.fk_Practice_Site,
            fk_Date_Start    = src.fk_Date_Start,
            fk_Date_End      = src.fk_Date_End,
            Contract_Number  = src.Contract_Number,
            NHS_Location_ID  = src.NHS_Location_ID,
            NHS_Site_ID      = src.NHS_Site_ID,
            Active           = src.Active,
            PDS_Plus         = src.PDS_Plus,
            Start_Date       = src.Start_Date,
            End_Date         = src.End_Date,
            UDA_Target       = src.UDA_Target,
            UDA_Value        = src.UDA_Value,
            UOA_Target       = src.UOA_Target,
            UOA_Value        = src.UOA_Value,
            DW_Updated_At    = SYSUTCDATETIME()
        FROM Gold.Fact_Contracts tgt
        INNER JOIN #src src ON tgt.bk_Contract_ID = src.bk_Contract_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Start] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_End] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Contract_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Location_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[PDS_Plus] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UOA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UOA_Value] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Start] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_End] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Contract_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Location_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[PDS_Plus] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Start_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[End_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UOA_Target] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UOA_Value] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_Contracts (
            Tenant_ID,
            bk_Contract_ID,
            fk_Practice_Site, fk_Date_Start, fk_Date_End,
            Contract_Number, NHS_Location_ID, NHS_Site_ID, Site_ID,
            Active, PDS_Plus, Start_Date, End_Date,
            UDA_Target, UDA_Value, UOA_Target, UOA_Value,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.bk_Contract_ID,
            src.fk_Practice_Site, src.fk_Date_Start, src.fk_Date_End,
            src.Contract_Number, src.NHS_Location_ID, src.NHS_Site_ID, src.Site_ID,
            src.Active, src.PDS_Plus, src.Start_Date, src.End_Date,
            src.UDA_Target, src.UDA_Value, src.UOA_Target, src.UOA_Value,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_Contracts tgt WHERE tgt.bk_Contract_ID = src.bk_Contract_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        -- Advance the watermark only after a successful load (inside TRY).
        UPDATE Gold.Load_Watermark
           SET Last_Loaded_At = @Run_Start, DW_Updated_At = SYSUTCDATETIME()
         WHERE Entity_Name = 'Fact_Contracts';
        IF @@ROWCOUNT = 0
            INSERT INTO Gold.Load_Watermark (Entity_Name, Last_Loaded_At, DW_Updated_At)
            VALUES ('Fact_Contracts', @Run_Start, SYSUTCDATETIME());

        DROP TABLE #src;
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
