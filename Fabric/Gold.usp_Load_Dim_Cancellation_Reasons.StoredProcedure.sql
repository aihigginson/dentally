--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Cancellation_Reasons] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Cancellation_Reasons
--  Author           :  AIH
--  Initital Date    :  21/05/2026
--  History          :
--    *01     21/05/2026  AIH Initial Release
--  To Run           :   DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Dim_Cancellation_Reasons @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Cancellation_Reasons]    Script Date: 21/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Cancellation_Reasons]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Cancellation_Reasons]
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
            Tenant_ID                                                                               AS Tenant_ID,
            LEFT(Cancellation_Reason_ID, 50)                                                        AS Cancellation_Reason_ID,
            CAST(CASE WHEN Archived = 1 THEN 0 ELSE 1 END AS BIT)                                  AS Is_Active,
            LEFT(Reason, 255)                                                                       AS Reason,
            LEFT(Reason_Type, 50)                                                                   AS Reason_Type,
            CAST(CASE WHEN LOWER(ISNULL(Reason,'')) LIKE '%short%notice%' THEN 1 ELSE 0 END AS BIT) AS Is_Short_Notice
        INTO #src
        FROM Silver.Appointment_Cancellation_Reasons
        WHERE Cancellation_Reason_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Cancellation_Reasons tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src
            WHERE Cancellation_Reason_ID = tgt.bk_Cancellation_Reason_ID
              AND Tenant_ID = tgt.Tenant_ID
        )
        AND tgt.pk_Cancellation_Reason <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Is_Active        = src.Is_Active,
            Reason           = src.Reason,
            Reason_Type      = src.Reason_Type,
            Is_Short_Notice  = src.Is_Short_Notice,
            DW_Updated_At    = SYSUTCDATETIME()
        FROM Gold.Dim_Cancellation_Reasons tgt
        INNER JOIN #src src
            ON tgt.bk_Cancellation_Reason_ID = src.Cancellation_Reason_ID
           AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(tgt.[Is_Active]       AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.[Reason]          AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.[Reason_Type]     AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.[Is_Short_Notice] AS VARCHAR(500)), '')
        )) <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(src.[Is_Active]       AS VARCHAR(500)), ''),
            ISNULL(CAST(src.[Reason]          AS VARCHAR(500)), ''),
            ISNULL(CAST(src.[Reason_Type]     AS VARCHAR(500)), ''),
            ISNULL(CAST(src.[Is_Short_Notice] AS VARCHAR(500)), '')
        ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_base BIGINT = ISNULL((SELECT MAX(pk_Cancellation_Reason) FROM Gold.Dim_Cancellation_Reasons WHERE pk_Cancellation_Reason > 0), 0);
        INSERT INTO Gold.Dim_Cancellation_Reasons (
            pk_Cancellation_Reason, Tenant_ID, bk_Cancellation_Reason_ID,
            Is_Active, Reason, Reason_Type, Is_Short_Notice,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Cancellation_Reason_ID),
            src.Tenant_ID, src.Cancellation_Reason_ID,
            src.Is_Active, src.Reason, src.Reason_Type, src.Is_Short_Notice,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM Gold.Dim_Cancellation_Reasons tgt
            WHERE tgt.bk_Cancellation_Reason_ID = src.Cancellation_Reason_ID
              AND tgt.Tenant_ID = src.Tenant_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists
        INSERT INTO Gold.Dim_Cancellation_Reasons (pk_Cancellation_Reason, Tenant_ID, bk_Cancellation_Reason_ID, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, '-1', SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Cancellation_Reasons WHERE pk_Cancellation_Reason = -1);

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
