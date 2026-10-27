--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Silver].[usp_Load_Recall_Reminders] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Silver.usp_Load_Recall_Reminders
--  Author           :  AIH
--  Initital Date    :  26/10/2026
--  History          :
--    *01     26/10/2026  AIH Initial Release
--  To Run           :  DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Silver.usp_Load_Recall_Reminders @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
--  Decodes the reminders JSON array from Bronze.Recalls with OPENJSON, one row per
--  reminder actually sent. See Silver.Recall_Reminders.Table.sql for why the scalar
--  first_/second_reminder_* fields cannot be used: Dentally populates first_reminder_id
--  with the NEWEST reminder's GUID and never populates the second at all.
--
--  ==> THE ARRAY IS NEWEST-FIRST, SO Reminder_Seq IS NOT THE ARRAY INDEX. <== Ordering by
--  Sent_At ASC is what makes seq 1 the genuine first chase. Using [key] from OPENJSON would
--  number them backwards and reproduce exactly the error this replaces.
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Silver].[usp_Load_Recall_Reminders]    Script Date: 26/10/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Silver].[usp_Load_Recall_Reminders]
GO
CREATE PROCEDURE [Silver].[usp_Load_Recall_Reminders]
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

        -- Each element: { "type": "SMS", "id": "<guid>", "date": "2026-10-25T10:51:45.123+01:00",
        --                 "template_name": "- OAB Dental recall 1" }
        -- The offset is kept out of the cast deliberately: LEFT(...,19) takes the LOCAL wall
        -- clock the practice saw, which is what every other date in this warehouse already is.
        -- Casting the full offset would shift an October reminder by an hour against the
        -- Due_Date it is compared with.
        DROP TABLE IF EXISTS #raw;
        SELECT
              r.Tenant_ID
            , CAST(r.ID AS VARCHAR(255))                              AS bk_Recall_ID
            , NULLIF(TRIM(rem.id), '')                                AS bk_Reminder_ID
            , NULLIF(TRIM(rem.type), '')                              AS Reminder_Type
            , TRY_CAST(LEFT(NULLIF(TRIM(rem.date), ''), 19) AS DATETIME2(3)) AS Sent_At
            , NULLIF(TRIM(rem.template_name), '')                     AS Template_Name
        INTO #raw
        FROM Bronze.Recalls r
        CROSS APPLY OPENJSON(r.Reminders)
        WITH (
            type          VARCHAR(50)  '$.type',
            id            VARCHAR(255) '$.id',
            date          VARCHAR(50)  '$.date',
            template_name VARCHAR(255) '$.template_name'
        ) rem
        WHERE r.ID IS NOT NULL
          AND r.Reminders IS NOT NULL
          AND LEN(LTRIM(RTRIM(r.Reminders))) > 2       -- excludes NULL and the empty array '[]'
          AND NULLIF(TRIM(rem.id), '') IS NOT NULL;    -- the grain key; an element without one
                                                       -- cannot be identified or de-duplicated

        -- ==> SEQUENCE BY DATE, IN A SEPARATE STEP. <== A window function cannot sit in the
        -- same SELECT as the CROSS APPLY that feeds it, and a temp table beats re-reading the
        -- JSON in a CTE -- in Fabric a re-referenced CTE re-evaluates its source.
        -- bk_Reminder_ID breaks the tie so the numbering is stable when two reminders share a
        -- second, which the live data does (ids differing only in the final character).
        DROP TABLE IF EXISTS #src;
        SELECT
              Tenant_ID, bk_Recall_ID, bk_Reminder_ID, Reminder_Type, Sent_At, Template_Name
            , CAST(ROW_NUMBER() OVER (PARTITION BY Tenant_ID, bk_Recall_ID
                                      ORDER BY Sent_At ASC, bk_Reminder_ID ASC) AS SMALLINT)
                                                                      AS Reminder_Seq
        INTO #src
        FROM #raw;

        -- Remove reminders no longer in source. A recall whose array has been emptied loses
        -- its rows here, which is correct: the array is the authority on what was sent.
        DELETE tgt
        FROM Silver.Recall_Reminders tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src src
            WHERE src.Tenant_ID      = tgt.Tenant_ID
              AND src.bk_Recall_ID   = tgt.bk_Recall_ID
              AND src.bk_Reminder_ID = tgt.bk_Reminder_ID
        );
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows. Reminder_Seq IS in the hash: a reminder that arrives late
        -- renumbers the ones after it, and leaving the sequence out of the comparison would
        -- leave the old numbering in place for ever -- the V235 trap.
        UPDATE tgt SET
              Reminder_Seq  = src.Reminder_Seq
            , Reminder_Type = src.Reminder_Type
            , Sent_At       = src.Sent_At
            , Template_Name = src.Template_Name
            , DW_Updated_At = CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM Silver.Recall_Reminders tgt
        JOIN #src src
            ON  src.Tenant_ID      = tgt.Tenant_ID
            AND src.bk_Recall_ID   = tgt.bk_Recall_ID
            AND src.bk_Reminder_ID = tgt.bk_Reminder_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
                ISNULL(CAST(tgt.Reminder_Seq  AS VARCHAR(10)),  ''),
                ISNULL(CAST(tgt.Reminder_Type AS VARCHAR(50)),  ''),
                ISNULL(CAST(tgt.Sent_At       AS VARCHAR(30)),  ''),
                ISNULL(CAST(tgt.Template_Name AS VARCHAR(255)), '')))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
                ISNULL(CAST(src.Reminder_Seq  AS VARCHAR(10)),  ''),
                ISNULL(CAST(src.Reminder_Type AS VARCHAR(50)),  ''),
                ISNULL(CAST(src.Sent_At       AS VARCHAR(30)),  ''),
                ISNULL(CAST(src.Template_Name AS VARCHAR(255)), '')));
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Silver.Recall_Reminders (
            Tenant_ID, bk_Recall_ID, bk_Reminder_ID, Reminder_Seq, Reminder_Type,
            Sent_At, Template_Name, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_Recall_ID, src.bk_Reminder_ID, src.Reminder_Seq,
            src.Reminder_Type, src.Sent_At, src.Template_Name,
            CAST(SYSUTCDATETIME() AS DATETIME2(3)),
            CAST(SYSUTCDATETIME() AS DATETIME2(3))
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM Silver.Recall_Reminders tgt
            WHERE tgt.Tenant_ID      = src.Tenant_ID
              AND tgt.bk_Recall_ID   = src.bk_Recall_ID
              AND tgt.bk_Reminder_ID = src.bk_Reminder_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #raw;
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
