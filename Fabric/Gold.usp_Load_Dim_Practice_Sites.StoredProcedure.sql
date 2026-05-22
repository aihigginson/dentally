--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Practice_Sites] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Practice_Sites
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID, Mon/Tue/etc. -> Monday/Tuesday/etc., lowercase Silver.Sites cols)
--    *05     22/05/2026  AIH Add Practice_Site_Count (1 real, 0 sentinel) for SUM-based measures
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Practice_Sites @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Practice_Sites]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Practice_Sites]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Practice_Sites]
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
            s.Site_ID                                               AS Site_ID,
            NULLIF(TRIM(s.Name),'')                                 AS Site_Name,
            CAST(ISNULL(s.Active,0) AS BIT)                         AS Site_Active,
            NULLIF(TRIM(s.Address_Line_1),'')                       AS Site_Address_Line_1,
            NULLIF(TRIM(s.Address_Line_2),'')                       AS Site_Address_Line_2,
            NULLIF(TRIM(s.Town),'')                                 AS Site_Town,
            NULLIF(TRIM(s.Postcode),'')                             AS Site_Postcode,
            NULLIF(TRIM(s.Phone_Number),'')                         AS Site_Phone,
            NULLIF(TRIM(s.Website),'')                              AS Site_Website,
            NULLIF(TRIM(s.Logo_URL),'')                             AS Site_Logo_URL,
            TRY_CAST(s.Default_Payment_Plan_ID AS INT)              AS Site_Default_Payment_Plan_ID,
            TRY_CAST(s.Monday_Open AS TIME(0))                      AS Monday_Open,
            TRY_CAST(s.Monday_Close AS TIME(0))                     AS Monday_Close,
            TRY_CAST(s.Tuesday_Open AS TIME(0))                     AS Tuesday_Open,
            TRY_CAST(s.Tuesday_Close AS TIME(0))                    AS Tuesday_Close,
            TRY_CAST(s.Wednesday_Open AS TIME(0))                   AS Wednesday_Open,
            TRY_CAST(s.Wednesday_Close AS TIME(0))                  AS Wednesday_Close,
            TRY_CAST(s.Thursday_Open AS TIME(0))                    AS Thursday_Open,
            TRY_CAST(s.Thursday_Close AS TIME(0))                   AS Thursday_Close,
            TRY_CAST(s.Friday_Open AS TIME(0))                      AS Friday_Open,
            TRY_CAST(s.Friday_Close AS TIME(0))                     AS Friday_Close,
            NULLIF(TRIM(s.Practice_ID),'')                          AS Practice_ID,
            NULLIF(TRIM(p.Practice_Name),'')                        AS Practice_Name,
            NULLIF(TRIM(p.Address_Line_1),'')                       AS Practice_Address_Line_1,
            NULLIF(TRIM(p.Address_Line_2),'')                       AS Practice_Address_Line_2,
            NULLIF(TRIM(p.Town),'')                                 AS Practice_Town,
            NULLIF(TRIM(p.Postcode),'')                             AS Practice_Postcode,
            CAST(p.Phone_Number AS VARCHAR(50))                     AS Practice_Phone,
            NULLIF(TRIM(p.Email_Address),'')                        AS Practice_Email,
            NULLIF(TRIM(p.Website),'')                              AS Practice_Website,
            CAST(ISNULL(p.NHS,0) AS BIT)                            AS Practice_NHS,
            NULLIF(TRIM(p.Time_Zone),'')                            AS Practice_Time_Zone,
            CAST(1 AS INT)                                          AS Practice_Site_Count
        INTO #src
        FROM Silver.Sites s
        LEFT JOIN Silver.Practice p ON p.Practice_ID = s.Practice_ID AND p.Tenant_ID = s.Tenant_ID
        WHERE s.Site_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Practice_Sites tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Site_ID = tgt.Site_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Practice_Site <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Site_Name                   = src.Site_Name,
            Site_Active                 = src.Site_Active,
            Site_Address_Line_1         = src.Site_Address_Line_1,
            Site_Address_Line_2         = src.Site_Address_Line_2,
            Site_Town                   = src.Site_Town,
            Site_Postcode               = src.Site_Postcode,
            Site_Phone                  = src.Site_Phone,
            Site_Website                = src.Site_Website,
            Site_Logo_URL               = src.Site_Logo_URL,
            Site_Default_Payment_Plan_ID= src.Site_Default_Payment_Plan_ID,
            Monday_Open                 = src.Monday_Open,
            Monday_Close                = src.Monday_Close,
            Tuesday_Open                = src.Tuesday_Open,
            Tuesday_Close               = src.Tuesday_Close,
            Wednesday_Open              = src.Wednesday_Open,
            Wednesday_Close             = src.Wednesday_Close,
            Thursday_Open               = src.Thursday_Open,
            Thursday_Close              = src.Thursday_Close,
            Friday_Open                 = src.Friday_Open,
            Friday_Close                = src.Friday_Close,
            Practice_ID                 = src.Practice_ID,
            Practice_Name               = src.Practice_Name,
            Practice_Address_Line_1     = src.Practice_Address_Line_1,
            Practice_Address_Line_2     = src.Practice_Address_Line_2,
            Practice_Town               = src.Practice_Town,
            Practice_Postcode           = src.Practice_Postcode,
            Practice_Phone              = src.Practice_Phone,
            Practice_Email              = src.Practice_Email,
            Practice_Website            = src.Practice_Website,
            Practice_NHS                = src.Practice_NHS,
            Practice_Time_Zone          = src.Practice_Time_Zone,
            DW_Updated_At               = SYSUTCDATETIME()
        FROM Gold.Dim_Practice_Sites tgt
        INNER JOIN #src src ON tgt.Site_ID = src.Site_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Site_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Address_Line_1] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Address_Line_2] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Town] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Postcode] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Website] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_Logo_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Monday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Monday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Tuesday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Tuesday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Wednesday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Wednesday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Thursday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Thursday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Friday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Friday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Address_Line_1] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Address_Line_2] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Town] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Postcode] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Website] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_NHS] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_Time_Zone] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Site_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Address_Line_1] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Address_Line_2] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Town] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Postcode] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Website] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_Logo_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Monday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Monday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Tuesday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Tuesday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Wednesday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Wednesday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Thursday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Thursday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Friday_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Friday_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Address_Line_1] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Address_Line_2] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Town] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Postcode] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Website] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_NHS] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_Time_Zone] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Practice_Site_base BIGINT = ISNULL((SELECT MAX(pk_Practice_Site) FROM Gold.Dim_Practice_Sites WHERE pk_Practice_Site > 0), 0);
        INSERT INTO Gold.Dim_Practice_Sites (
            pk_Practice_Site,
            Tenant_ID,
            Site_ID, Site_Name, Site_Active, Site_Address_Line_1, Site_Address_Line_2,
            Site_Town, Site_Postcode, Site_Phone, Site_Website, Site_Logo_URL, Site_Default_Payment_Plan_ID,
            Monday_Open, Monday_Close, Tuesday_Open, Tuesday_Close, Wednesday_Open, Wednesday_Close,
            Thursday_Open, Thursday_Close, Friday_Open, Friday_Close,
            Practice_ID, Practice_Name, Practice_Address_Line_1, Practice_Address_Line_2,
            Practice_Town, Practice_Postcode, Practice_Phone, Practice_Email,
            Practice_Website, Practice_NHS, Practice_Time_Zone, Practice_Site_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Practice_Site_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Site_ID),
            src.Tenant_ID,
            src.Site_ID, src.Site_Name, src.Site_Active, src.Site_Address_Line_1, src.Site_Address_Line_2,
            src.Site_Town, src.Site_Postcode, src.Site_Phone, src.Site_Website, src.Site_Logo_URL, src.Site_Default_Payment_Plan_ID,
            src.Monday_Open, src.Monday_Close, src.Tuesday_Open, src.Tuesday_Close, src.Wednesday_Open, src.Wednesday_Close,
            src.Thursday_Open, src.Thursday_Close, src.Friday_Open, src.Friday_Close,
            src.Practice_ID, src.Practice_Name, src.Practice_Address_Line_1, src.Practice_Address_Line_2,
            src.Practice_Town, src.Practice_Postcode, src.Practice_Phone, src.Practice_Email,
            src.Practice_Website, src.Practice_NHS, src.Practice_Time_Zone, src.Practice_Site_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Practice_Sites tgt WHERE tgt.Site_ID = src.Site_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Practice_Sites (pk_Practice_Site, Tenant_ID, Site_ID, Practice_Site_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, '-1', 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Practice_Sites WHERE pk_Practice_Site = -1);
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
