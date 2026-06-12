--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Treatments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Treatments
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     22/05/2026  AIH Add Treatment_Count (1 real, 0 sentinel) for SUM-based measures
--    *05     09/06/2026  AIH Add Standard_Treatment_Category via LEFT JOIN Input.Treatment_Category_Map
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Treatments @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Treatments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Treatments]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Treatments]
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
            t.Tenant_ID                                     AS Tenant_ID,
            CAST(t.Id AS INT)                               AS Treatment_ID,
            CAST(t.Code AS INT)                             AS Treatment_Code,
            NULLIF(TRIM(t.Nomenclature),'')                 AS Nomenclature,
            NULLIF(TRIM(t.Patient_Nomenclature),'')         AS Patient_Nomenclature,
            NULLIF(TRIM(t.Description),'')                  AS Description,
            NULLIF(TRIM(t.Patient_Description),'')          AS Patient_Description,
            NULLIF(TRIM(t.Notes),'')                        AS Notes,
            NULLIF(TRIM(t.Region),'')                       AS Region,
            CAST(t.UDA_Band AS INT)                         AS UDA_Band,
            CAST(t.NHS_Treatment_Cat AS INT)                AS NHS_Treatment_Cat,
            CAST(t.Treatment_Category_ID AS INT)            AS Treatment_Category_ID,
            NULLIF(TRIM(tc.Name),'')                        AS Treatment_Category_Name,
            COALESCE(NULLIF(TRIM(m.Standard_Treatment_Category),''), LEFT(NULLIF(TRIM(tc.Name),''), 100)) AS Standard_Treatment_Category,
            TRY_CAST(NULLIF(TRIM(t.Created_At),'') AS datetime2(3)) AS Created_Date,
            TRY_CAST(NULLIF(TRIM(t.Updated_At),'') AS datetime2(3)) AS Updated_Date,
            CAST(1 AS INT)                                            AS Treatment_Count
        INTO #src
        FROM Silver.Treatments t
        LEFT JOIN Silver.Treatment_Categories tc ON tc.Id = t.Treatment_Category_ID AND tc.Tenant_ID = t.Tenant_ID
        LEFT JOIN Input.Treatment_Category_Map m  ON m.Tenant_ID = t.Tenant_ID AND m.Source_Treatment_Category = NULLIF(TRIM(tc.Name),'')
        WHERE t.Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Treatments tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Treatment_ID = tgt.Treatment_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Treatment <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Treatment_Code          = src.Treatment_Code,
            Nomenclature            = src.Nomenclature,
            Patient_Nomenclature    = src.Patient_Nomenclature,
            Description             = src.Description,
            Patient_Description     = src.Patient_Description,
            Notes                   = src.Notes,
            Region                  = src.Region,
            UDA_Band                = src.UDA_Band,
            NHS_Treatment_Cat       = src.NHS_Treatment_Cat,
            Treatment_Category_ID        = src.Treatment_Category_ID,
            Treatment_Category_Name      = src.Treatment_Category_Name,
            Standard_Treatment_Category  = src.Standard_Treatment_Category,
            Updated_Date                 = src.Updated_Date,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Dim_Treatments tgt
        INNER JOIN #src src ON tgt.Treatment_ID = src.Treatment_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Treatment_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Region] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Category_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Treatment_Category_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Standard_Treatment_Category] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Treatment_Code] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Nomenclature] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Description] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Notes] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Region] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Treatment_Cat] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Category_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Treatment_Category_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Standard_Treatment_Category] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Treatment_base BIGINT = ISNULL((SELECT MAX(pk_Treatment) FROM Gold.Dim_Treatments WHERE pk_Treatment > 0), 0);
        INSERT INTO Gold.Dim_Treatments (
            pk_Treatment,
            Tenant_ID,
            Treatment_ID, Treatment_Code, Nomenclature, Patient_Nomenclature, Description,
            Patient_Description, Notes, Region, UDA_Band, NHS_Treatment_Cat,
            Treatment_Category_ID, Treatment_Category_Name, Standard_Treatment_Category,
            Created_Date, Updated_Date,
            Treatment_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Treatment_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Treatment_ID),
            src.Tenant_ID,
            src.Treatment_ID, src.Treatment_Code, src.Nomenclature, src.Patient_Nomenclature, src.Description,
            src.Patient_Description, src.Notes, src.Region, src.UDA_Band, src.NHS_Treatment_Cat,
            src.Treatment_Category_ID, src.Treatment_Category_Name, src.Standard_Treatment_Category,
            src.Created_Date, src.Updated_Date,
            src.Treatment_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Treatments tgt WHERE tgt.Treatment_ID = src.Treatment_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Treatments (pk_Treatment, Tenant_ID, Treatment_ID, Treatment_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Treatments WHERE pk_Treatment = -1);
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
