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
            c.UOA_Value
        INTO #src
        FROM Silver.Contracts c
        WHERE c.Id IS NOT NULL;

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
           ISNULL(CAST(tgt.[UOA_Value] AS VARCHAR(500)), '')
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
           ISNULL(CAST(src.[UOA_Value] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_NHS_Contract_base BIGINT = ISNULL((SELECT MAX(pk_NHS_Contract) FROM Gold.Dim_NHS_Contracts WHERE pk_NHS_Contract > 0), 0);

        INSERT INTO Gold.Dim_NHS_Contracts (
            pk_NHS_Contract, Tenant_ID, bk_Contract_ID,
            Contract_Number, Contract_Name, Site_ID, Active, PDS_Plus,
            NHS_Location_ID, NHS_Site_ID, Start_Date, End_Date,
            UDA_Target, UDA_Value, UOA_Target, UOA_Value,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_NHS_Contract_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.bk_Contract_ID),
            src.Tenant_ID, src.bk_Contract_ID,
            src.Contract_Number, src.Contract_Name, src.Site_ID, src.Active, src.PDS_Plus,
            src.NHS_Location_ID, src.NHS_Site_ID, src.Start_Date, src.End_Date,
            src.UDA_Target, src.UDA_Value, src.UOA_Target, src.UOA_Value,
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
