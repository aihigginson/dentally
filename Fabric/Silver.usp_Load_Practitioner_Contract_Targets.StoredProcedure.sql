--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Practitioner_Contract_Targets] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Practitioner_Contract_Targets
--  Author           :  AIH
--  Initital Date    :  12/06/2026
--  History          :
--    *01     12/06/2026  AIH Initial Release
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Silver.usp_Load_Practitioner_Contract_Targets @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
--  Parses the contract_targets JSON array from Bronze.Practitioners
--  using OPENJSON. Each practitioner can be assigned to multiple contracts
--  with individual UDA/UOA targets. Grain: Tenant x Practitioner x Contract.
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Practitioner_Contract_Targets]    Script Date: 12/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Practitioner_Contract_Targets]
GO
CREATE PROCEDURE [Silver].[usp_Load_Practitioner_Contract_Targets]
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
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        -- Parse contract_targets JSON array from Bronze.Practitioners.
        -- Each element: { "id": N, "contract_id": "...", "uda_target": N,
        --                 "uoa_target": N, "default": true/false }
        SELECT
            p.Tenant_ID,
            p.Practitioner_ID                              AS bk_Practitioner_ID,
            NULLIF(TRIM(ct.contract_id), '')               AS bk_Contract_ID,
            TRY_CAST(ct.uda_target AS DECIMAL(18,4))       AS UDA_Target,
            TRY_CAST(ct.uoa_target AS DECIMAL(18,4))       AS UOA_Target,
            ct.is_default                                  AS Is_Default
        INTO #src
        FROM Bronze.Practitioners p
        CROSS APPLY OPENJSON(p.Contract_Targets_String)
        WITH (
            contract_id  VARCHAR(50)  '$.contract_id',
            uda_target   VARCHAR(50)  '$.uda_target',
            uoa_target   VARCHAR(50)  '$.uoa_target',
            is_default   BIT          '$.default'
        ) ct
        WHERE p.Practitioner_ID IS NOT NULL
          AND p.Contract_Targets_String IS NOT NULL
          AND LEN(LTRIM(RTRIM(p.Contract_Targets_String))) > 2  -- exclude NULL and empty array '[]'
          AND NULLIF(TRIM(ct.contract_id), '') IS NOT NULL;     -- skip malformed entries with no contract_id
                                                                -- (bk_Contract_ID is the grain key; a target
                                                                -- without a contract is meaningless)

        -- Remove rows no longer in source
        DELETE tgt
        FROM Silver.Practitioner_Contract_Targets tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src src
            WHERE src.Tenant_ID          = tgt.Tenant_ID
              AND src.bk_Practitioner_ID = tgt.bk_Practitioner_ID
              AND src.bk_Contract_ID     = tgt.bk_Contract_ID
        );
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            UDA_Target   = src.UDA_Target,
            UOA_Target   = src.UOA_Target,
            Is_Default   = src.Is_Default,
            DW_Updated_At = CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM Silver.Practitioner_Contract_Targets tgt
        JOIN #src src
            ON  src.Tenant_ID          = tgt.Tenant_ID
            AND src.bk_Practitioner_ID = tgt.bk_Practitioner_ID
            AND src.bk_Contract_ID     = tgt.bk_Contract_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
                ISNULL(CAST(tgt.UDA_Target AS VARCHAR(50)), ''),
                ISNULL(CAST(tgt.UOA_Target AS VARCHAR(50)), ''),
                ISNULL(CAST(tgt.Is_Default AS VARCHAR(5)),  '')))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
                ISNULL(CAST(src.UDA_Target AS VARCHAR(50)), ''),
                ISNULL(CAST(src.UOA_Target AS VARCHAR(50)), ''),
                ISNULL(CAST(src.Is_Default AS VARCHAR(5)),  '')));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Silver.Practitioner_Contract_Targets (
            Tenant_ID, bk_Practitioner_ID, bk_Contract_ID,
            UDA_Target, UOA_Target, Is_Default,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Practitioner_ID, src.bk_Contract_ID,
            src.UDA_Target, src.UOA_Target, src.Is_Default,
            CAST(SYSUTCDATETIME() AS DATETIME2(3)),
            CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM Silver.Practitioner_Contract_Targets tgt
            WHERE tgt.Tenant_ID          = src.Tenant_ID
              AND tgt.bk_Practitioner_ID = src.bk_Practitioner_ID
              AND tgt.bk_Contract_ID     = src.bk_Contract_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
