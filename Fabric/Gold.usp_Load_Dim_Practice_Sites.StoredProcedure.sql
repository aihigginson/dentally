--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Practice_Sites
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
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
            s.Site_Id                                               AS Site_ID,
            NULLIF(TRIM(s.Name),'')                                 AS Site_Name,
            CAST(ISNULL(s.active,0) AS BIT)                         AS Site_Active,
            NULLIF(TRIM(s.address_line_1),'')                       AS Site_Address_Line_1,
            NULLIF(TRIM(s.address_line_2),'')                       AS Site_Address_Line_2,
            NULLIF(TRIM(s.town),'')                                 AS Site_Town,
            NULLIF(TRIM(s.postcode),'')                             AS Site_Postcode,
            NULLIF(TRIM(s.phone_number),'')                         AS Site_Phone,
            NULLIF(TRIM(s.website),'')                              AS Site_Website,
            NULLIF(TRIM(s.logo_url),'')                             AS Site_Logo_URL,
            TRY_CAST(s.default_payment_plan_id AS INT)              AS Site_Default_Payment_Plan_ID,
            TRY_CAST(s.monday_open AS TIME(0))                      AS Mon_Open,
            TRY_CAST(s.monday_close AS TIME(0))                     AS Mon_Close,
            TRY_CAST(s.tuesday_open AS TIME(0))                     AS Tue_Open,
            TRY_CAST(s.tuesday_close AS TIME(0))                    AS Tue_Close,
            TRY_CAST(s.wednesday_open AS TIME(0))                   AS Wed_Open,
            TRY_CAST(s.wednesday_close AS TIME(0))                  AS Wed_Close,
            TRY_CAST(s.thursday_open AS TIME(0))                    AS Thu_Open,
            TRY_CAST(s.thursday_close AS TIME(0))                   AS Thu_Close,
            TRY_CAST(s.friday_open AS TIME(0))                      AS Fri_Open,
            TRY_CAST(s.friday_close AS TIME(0))                     AS Fri_Close,
            NULLIF(TRIM(s.Practice_Id),'')                          AS Practice_ID,
            NULLIF(TRIM(p.Practice_Name),'')                        AS Practice_Name,
            NULLIF(TRIM(p.Address_Line_1),'')                       AS Practice_Address_Line_1,
            NULLIF(TRIM(p.Address_Line_2),'')                       AS Practice_Address_Line_2,
            NULLIF(TRIM(p.Town),'')                                 AS Practice_Town,
            NULLIF(TRIM(p.Postcode),'')                             AS Practice_Postcode,
            CAST(p.Phone_Number AS VARCHAR(50))                     AS Practice_Phone,
            NULLIF(TRIM(p.Email_Address),'')                        AS Practice_Email,
            NULLIF(TRIM(p.Website),'')                              AS Practice_Website,
            CAST(ISNULL(p.NHS,0) AS BIT)                            AS Practice_NHS,
            NULLIF(TRIM(p.Time_Zone),'')                            AS Practice_Time_Zone
        INTO #src
        FROM Silver.Sites s
        LEFT JOIN Silver.Practice p ON p.Practice_Id = s.Practice_Id AND p.Tenant_ID = s.Tenant_ID
        WHERE s.Site_Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Practice_Sites tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Site_ID = tgt.Site_ID AND Tenant_ID = tgt.Tenant_ID);
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
            Mon_Open                    = src.Mon_Open,
            Mon_Close                   = src.Mon_Close,
            Tue_Open                    = src.Tue_Open,
            Tue_Close                   = src.Tue_Close,
            Wed_Open                    = src.Wed_Open,
            Wed_Close                   = src.Wed_Close,
            Thu_Open                    = src.Thu_Open,
            Thu_Close                   = src.Thu_Close,
            Fri_Open                    = src.Fri_Open,
            Fri_Close                   = src.Fri_Close,
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
           ISNULL(CAST(tgt.[Mon_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mon_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Tue_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Tue_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Wed_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Wed_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Thu_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Thu_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Fri_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Fri_Close] AS VARCHAR(500)), ''),
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
           ISNULL(CAST(src.[Mon_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mon_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Tue_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Tue_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Wed_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Wed_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Thu_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Thu_Close] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Fri_Open] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Fri_Close] AS VARCHAR(500)), ''),
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
        INSERT INTO Gold.Dim_Practice_Sites (
            Tenant_ID,
            Site_ID, Site_Name, Site_Active, Site_Address_Line_1, Site_Address_Line_2,
            Site_Town, Site_Postcode, Site_Phone, Site_Website, Site_Logo_URL, Site_Default_Payment_Plan_ID,
            Mon_Open, Mon_Close, Tue_Open, Tue_Close, Wed_Open, Wed_Close,
            Thu_Open, Thu_Close, Fri_Open, Fri_Close,
            Practice_ID, Practice_Name, Practice_Address_Line_1, Practice_Address_Line_2,
            Practice_Town, Practice_Postcode, Practice_Phone, Practice_Email,
            Practice_Website, Practice_NHS, Practice_Time_Zone, DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID,
            src.Site_ID, src.Site_Name, src.Site_Active, src.Site_Address_Line_1, src.Site_Address_Line_2,
            src.Site_Town, src.Site_Postcode, src.Site_Phone, src.Site_Website, src.Site_Logo_URL, src.Site_Default_Payment_Plan_ID,
            src.Mon_Open, src.Mon_Close, src.Tue_Open, src.Tue_Close, src.Wed_Open, src.Wed_Close,
            src.Thu_Open, src.Thu_Close, src.Fri_Open, src.Fri_Close,
            src.Practice_ID, src.Practice_Name, src.Practice_Address_Line_1, src.Practice_Address_Line_2,
            src.Practice_Town, src.Practice_Postcode, src.Practice_Phone, src.Practice_Email,
            src.Practice_Website, src.Practice_NHS, src.Practice_Time_Zone, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Practice_Sites tgt WHERE tgt.Site_ID = src.Site_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

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
