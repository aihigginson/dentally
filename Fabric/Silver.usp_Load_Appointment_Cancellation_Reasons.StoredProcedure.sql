--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Appointment_Cancellation_Reasons] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Appointment_Cancellation_Reasons
--  Author           :  AIH
--  Initital Date    :  20/05/2026
--  History          :
--    *01     20/05/2026  AIH Initial Release
--    *02     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--  To Run           :   DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Silver.usp_Load_Appointment_Cancellation_Reasons @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Appointment_Cancellation_Reasons]    Script Date: 20/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Appointment_Cancellation_Reasons]
GO
CREATE PROCEDURE [Silver].[usp_Load_Appointment_Cancellation_Reasons]
(
      @Mode          VARCHAR(100) = 'TEST'
    , @Logging       smallint      = 1
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
            staged.*,
            CONVERT(VARBINARY(32), HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
        ISNULL(CAST(staged.[Archived]      AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reason]        AS VARCHAR(500)), ''),
        ISNULL(CAST(staged.[Reason_Type]   AS VARCHAR(500)), '')
        ))) AS _Hash
        INTO #src
        FROM (
            SELECT
                Tenant_ID                                                              AS [Tenant_ID],
                LEFT(ID, 50)                                                           AS [Cancellation_Reason_ID],
                -- Bronze.Active=1 means active (not archived); invert to Silver.Archived bit
                CASE WHEN Active = 1 THEN CAST(0 AS bit) ELSE CAST(1 AS bit) END      AS [Archived],
                LEFT(Reason, 255)                                                      AS [Reason],
                LEFT(Reason_Type, 50)                                                  AS [Reason_Type]
            FROM Bronze.Cancellation_Reasons
        ) AS staged;

        UPDATE tgt
        SET
            [Archived]      = src.[Archived],
            [Reason]        = src.[Reason],
            [Reason_Type]   = src.[Reason_Type],
            [DW_Updated_At] = SYSUTCDATETIME(),
            [_Row_Hash]     = src._Hash
        FROM [Silver].[Appointment_Cancellation_Reasons] AS tgt
        INNER JOIN #src AS src ON tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Cancellation_Reason_ID] = src.[Cancellation_Reason_ID]
        WHERE tgt.[_Row_Hash] <> src._Hash;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Silver].[Appointment_Cancellation_Reasons] (
            [Tenant_ID], [Cancellation_Reason_ID], [Archived], [Reason], [Reason_Type],
            [DW_Created_At], [DW_Updated_At], [_Row_Hash]
        )
        SELECT
            src.[Tenant_ID], src.[Cancellation_Reason_ID], src.[Archived], src.[Reason], src.[Reason_Type],
            SYSUTCDATETIME(), SYSUTCDATETIME(), src._Hash
        FROM #src AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM [Silver].[Appointment_Cancellation_Reasons] AS tgt
            WHERE tgt.[Tenant_ID] = src.[Tenant_ID] AND tgt.[Cancellation_Reason_ID] = src.[Cancellation_Reason_ID]
        );
        SET @My_Inserts = @@ROWCOUNT;

        DELETE tgt
        FROM [Silver].[Appointment_Cancellation_Reasons] AS tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src AS src
            WHERE src.[Tenant_ID] = tgt.[Tenant_ID] AND src.[Cancellation_Reason_ID] = tgt.[Cancellation_Reason_ID]
        );
        SET @My_Deletes = @@ROWCOUNT;

        DROP TABLE IF EXISTS #src;

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
