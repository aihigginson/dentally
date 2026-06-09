--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Acquisition_Sources] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Acquisition_Sources
--  Author           :  AIH
--  Initial Date     :  29/05/2026
--  History          :
--    *01     29/05/2026  AIH Initial Release
--    *02     09/06/2026  AIH Add Standard_Acquisition_Source via LEFT JOIN Input.Acquisition_Source_Map
--  To Run           :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Acquisition_Sources @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Acquisition_Sources]    Script Date: 29/05/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Acquisition_Sources]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Acquisition_Sources]
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
            s.Tenant_ID                                             AS Tenant_ID,
            s.Acquisition_Source_ID                                 AS Acquisition_Source_ID,
            CAST(ISNULL(s.Active, 0) AS BIT)                        AS Active,
            NULLIF(TRIM(s.Name), '')                                AS Name,
            COALESCE(NULLIF(TRIM(m.Standard_Acquisition_Source),''), LEFT(NULLIF(TRIM(s.Name),''), 100)) AS Standard_Acquisition_Source,
            NULLIF(TRIM(s.Notes), '')                               AS Notes,
            CAST(1 AS INT)                                          AS Acquisition_Source_Count
        INTO #src
        FROM Silver.Acquisition_Sources s
        LEFT JOIN Input.Acquisition_Source_Map m ON m.Tenant_ID = s.Tenant_ID AND m.Source_Acquisition_Source = NULLIF(TRIM(s.Name), '')
        WHERE s.Acquisition_Source_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Acquisition_Sources tgt
        WHERE NOT EXISTS (
            SELECT 1 FROM #src
            WHERE Acquisition_Source_ID = tgt.Acquisition_Source_ID
              AND Tenant_ID             = tgt.Tenant_ID
        )
        AND tgt.pk_Acquisition_Source <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Active                       = src.Active,
            Name                         = src.Name,
            Standard_Acquisition_Source  = src.Standard_Acquisition_Source,
            Notes                        = src.Notes,
            DW_Updated_At                = SYSUTCDATETIME()
        FROM Gold.Dim_Acquisition_Sources tgt
        INNER JOIN #src src
            ON tgt.Acquisition_Source_ID = src.Acquisition_Source_ID
           AND tgt.Tenant_ID             = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Active]                      AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Name]                        AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Standard_Acquisition_Source] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes]                       AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Active]                      AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Name]                        AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Standard_Acquisition_Source] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes]                       AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_base BIGINT = ISNULL((SELECT MAX(pk_Acquisition_Source) FROM Gold.Dim_Acquisition_Sources WHERE pk_Acquisition_Source > 0), 0);
        INSERT INTO Gold.Dim_Acquisition_Sources (
            pk_Acquisition_Source,
            Tenant_ID, Acquisition_Source_ID,
            Active, Name, Standard_Acquisition_Source, Notes,
            Acquisition_Source_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Acquisition_Source_ID),
            src.Tenant_ID, src.Acquisition_Source_ID,
            src.Active, src.Name, src.Standard_Acquisition_Source, src.Notes,
            src.Acquisition_Source_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (
            SELECT 1 FROM Gold.Dim_Acquisition_Sources tgt
            WHERE tgt.Acquisition_Source_ID = src.Acquisition_Source_ID
              AND tgt.Tenant_ID             = src.Tenant_ID
        );
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists
        INSERT INTO Gold.Dim_Acquisition_Sources (
            pk_Acquisition_Source, Tenant_ID, Acquisition_Source_ID,
            Acquisition_Source_Count, DW_Created_At, DW_Updated_At
        )
        SELECT -1, -1, '-1', 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Acquisition_Sources WHERE pk_Acquisition_Source = -1);

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
