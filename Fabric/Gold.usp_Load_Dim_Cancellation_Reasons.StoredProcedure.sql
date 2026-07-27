--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Cancellation_Reasons] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Cancellation_Reasons
--  Author           :  AIH
--  Initital Date    :  21/05/2026
--  History          :
--    *01     21/05/2026  AIH Initial Release
--    *02     22/05/2026  AIH Add Cancellation_Reason_Count (1 real, 0 sentinel) for SUM-based measures
--    *03     09/06/2026  AIH Add Standard_Cancellation_Reason via LEFT JOIN Input.Cancellation_Reason_Map
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
            cr.Tenant_ID                                                                               AS Tenant_ID,
            LEFT(cr.Cancellation_Reason_ID, 50)                                                        AS Cancellation_Reason_ID,
            CAST(CASE WHEN cr.Archived = 1 THEN 0 ELSE 1 END AS BIT)                                  AS Is_Active,
            LEFT(cr.Reason, 255)                                                                       AS Reason,
            COALESCE(NULLIF(TRIM(m.Standard_Cancellation_Reason),''), LEFT(cr.Reason, 100))             AS Standard_Cancellation_Reason,
            LEFT(cr.Reason_Type, 50)                                                                   AS Reason_Type,
            CAST(1 AS INT)                                                                             AS Cancellation_Reason_Count
        INTO #src
        FROM Silver.Appointment_Cancellation_Reasons cr
        LEFT JOIN Input.Cancellation_Reason_Map m ON m.Tenant_ID = cr.Tenant_ID AND m.Source_Cancellation_Reason = LEFT(cr.Reason, 255)
        WHERE cr.Cancellation_Reason_ID IS NOT NULL;

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
            Is_Active                    = src.Is_Active,
            Reason                       = src.Reason,
            Standard_Cancellation_Reason = src.Standard_Cancellation_Reason,
            Reason_Type                  = src.Reason_Type,
            DW_Updated_At                = SYSUTCDATETIME()
        FROM Gold.Dim_Cancellation_Reasons tgt
        INNER JOIN #src src
            ON tgt.bk_Cancellation_Reason_ID = src.Cancellation_Reason_ID
           AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(tgt.[Is_Active]                    AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.[Reason]                       AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.[Standard_Cancellation_Reason] AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.[Reason_Type]                  AS VARCHAR(500)), '')
        )) <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(src.[Is_Active]                    AS VARCHAR(500)), ''),
            ISNULL(CAST(src.[Reason]                       AS VARCHAR(500)), ''),
            ISNULL(CAST(src.[Standard_Cancellation_Reason] AS VARCHAR(500)), ''),
            ISNULL(CAST(src.[Reason_Type]                  AS VARCHAR(500)), '')
        ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_base BIGINT = ISNULL((SELECT MAX(pk_Cancellation_Reason) FROM Gold.Dim_Cancellation_Reasons WHERE pk_Cancellation_Reason > 0), 0);
        INSERT INTO Gold.Dim_Cancellation_Reasons (
            pk_Cancellation_Reason, Tenant_ID, bk_Cancellation_Reason_ID,
            Is_Active, Reason, Standard_Cancellation_Reason, Reason_Type,
            Cancellation_Reason_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Cancellation_Reason_ID),
            src.Tenant_ID, src.Cancellation_Reason_ID,
            src.Is_Active, src.Reason, src.Standard_Cancellation_Reason, src.Reason_Type,
            src.Cancellation_Reason_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM Gold.Dim_Cancellation_Reasons tgt
            WHERE tgt.bk_Cancellation_Reason_ID = src.Cancellation_Reason_ID
              AND tgt.Tenant_ID = src.Tenant_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists, labelled "No reason recorded" so cancellations
        -- with no source reason show a meaningful bucket (not a blank) in by-reason visuals.
        INSERT INTO Gold.Dim_Cancellation_Reasons (pk_Cancellation_Reason, Tenant_ID, bk_Cancellation_Reason_ID, Reason, Standard_Cancellation_Reason, Cancellation_Reason_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, '-1', 'No reason recorded', 'No reason recorded', 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Cancellation_Reasons WHERE pk_Cancellation_Reason = -1);

        -- Backfill the label on an already-seeded -1 row (was NULL before this change).
        UPDATE Gold.Dim_Cancellation_Reasons
        SET Reason = 'No reason recorded', Standard_Cancellation_Reason = 'No reason recorded', DW_Updated_At = SYSUTCDATETIME()
        WHERE pk_Cancellation_Reason = -1 AND ISNULL(Reason,'') <> 'No reason recorded';

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
