--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Practitioners] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Practitioners
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *05     22/05/2026  AIH Add Practitioner_Count (1 real, 0 sentinel) for SUM-based measures
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Practitioners @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Practitioners]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Practitioners]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Practitioners]
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
            Tenant_ID                                                       AS Tenant_ID,
            CAST(Practitioner_ID AS INT)                                    AS Practitioner_ID,
            CAST(User_ID AS INT)                                            AS User_ID,
            NULLIF(TRIM(User_Title),'')                                     AS Title,
            NULLIF(TRIM(User_First_Name),'')                                AS First_Name,
            NULLIF(TRIM(User_Middle_Name),'')                               AS Middle_Name,
            NULLIF(TRIM(User_Last_Name),'')                                 AS Last_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(User_Title),''),
                NULLIF(TRIM(User_First_Name),''),
                NULLIF(TRIM(User_Last_Name),'')),'')                        AS Full_Name,
            NULLIF(TRIM(User_Email),'')                                     AS Email,
            NULLIF(TRIM(User_Mobile_Phone),'')                              AS Mobile_Phone,
            NULLIF(TRIM(User_Role),'')                                      AS Role,
            CAST(User_Permission_Level AS INT)                              AS Permission_Level,
            CAST(ISNULL(Practitioner_Active,0) AS BIT)                      AS Active,
            NULLIF(TRIM(Practitioner_Colour),'')                            AS Colour,
            NULLIF(TRIM(Practitioner_GDC_Number),'')                        AS GDC_Number,
            NULLIF(TRIM(Practitioner_NHS_Number),'')                        AS NHS_Number,
            NULLIF(TRIM(Practitioner_Site_ID),'')                           AS Site_ID,
            NULLIF(TRIM(Practitioner_Default_Contract_ID),'')               AS Default_Contract_ID,
            NULLIF(TRIM(Contract_Targets_String),'')                        AS Contract_Targets_String,
            NULLIF(TRIM(User_Image_URL),'')                                 AS Image_URL,
            TRY_CAST(NULLIF(TRIM(User_Last_Login),'') AS DATE)              AS Last_Login_Date,
            TRY_CAST(NULLIF(TRIM(User_Created_At),'') AS datetime2(3))      AS Created_Date,
            TRY_CAST(NULLIF(TRIM(User_Updated_At),'') AS datetime2(3))      AS Updated_Date,
            CAST(1 AS INT)                                                          AS Practitioner_Count
        INTO #src
        FROM Silver.Practitioners
        WHERE Practitioner_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Practitioners tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Practitioner_ID = tgt.Practitioner_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Practitioner <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            User_ID                 = src.User_ID,
            Title                   = src.Title,
            First_Name              = src.First_Name,
            Middle_Name             = src.Middle_Name,
            Last_Name               = src.Last_Name,
            Full_Name               = src.Full_Name,
            Email                   = src.Email,
            Mobile_Phone            = src.Mobile_Phone,
            Role                    = src.Role,
            Permission_Level        = src.Permission_Level,
            Active                  = src.Active,
            Colour                  = src.Colour,
            GDC_Number              = src.GDC_Number,
            NHS_Number              = src.NHS_Number,
            Site_ID                 = src.Site_ID,
            Default_Contract_ID     = src.Default_Contract_ID,
            Contract_Targets_String = src.Contract_Targets_String,
            Image_URL               = src.Image_URL,
            Last_Login_Date         = src.Last_Login_Date,
            Updated_Date            = src.Updated_Date,
            DW_Updated_At           = SYSUTCDATETIME()
        FROM Gold.Dim_Practitioners tgt
        INNER JOIN #src src ON tgt.Practitioner_ID = src.Practitioner_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[User_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[GDC_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NHS_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Default_Contract_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Contract_Targets_String] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[User_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Active] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Colour] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[GDC_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NHS_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Default_Contract_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Contract_Targets_String] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Practitioner_base BIGINT = ISNULL((SELECT MAX(pk_Practitioner) FROM Gold.Dim_Practitioners WHERE pk_Practitioner > 0), 0);
        INSERT INTO Gold.Dim_Practitioners (
            pk_Practitioner,
            Tenant_ID,
            Practitioner_ID, User_ID, Title, First_Name, Middle_Name, Last_Name, Full_Name,
            Email, Mobile_Phone, Role, Permission_Level, Active, Colour, GDC_Number, NHS_Number,
            Site_ID, Default_Contract_ID, Contract_Targets_String, Image_URL,
            Last_Login_Date, Created_Date, Updated_Date, Practitioner_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Practitioner_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Practitioner_ID),
            src.Tenant_ID,
            src.Practitioner_ID, src.User_ID, src.Title, src.First_Name, src.Middle_Name, src.Last_Name, src.Full_Name,
            src.Email, src.Mobile_Phone, src.Role, src.Permission_Level, src.Active, src.Colour, src.GDC_Number, src.NHS_Number,
            src.Site_ID, src.Default_Contract_ID, src.Contract_Targets_String, src.Image_URL,
            src.Last_Login_Date, src.Created_Date, src.Updated_Date, src.Practitioner_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Practitioners tgt WHERE tgt.Practitioner_ID = src.Practitioner_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Practitioners (pk_Practitioner, Tenant_ID, Practitioner_ID, Practitioner_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Practitioners WHERE pk_Practitioner = -1);
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
