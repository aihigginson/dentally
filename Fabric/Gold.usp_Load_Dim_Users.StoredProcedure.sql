--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Users] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Users
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     30/04/2026  AIH Add Is_Current to INSERT (NOT NULL column omitted from column list)
--    *03     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *04     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *05     20/05/2026  AIH Column naming convention fixes (ID/_ID)
--    *06     22/05/2026  AIH Add User_Count (1 real, 0 sentinel) for SUM-based measures
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Users @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Users]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Users]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Users]
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
            Tenant_ID                                           AS Tenant_ID,
            CAST(Id AS INT)                                     AS bk_User_ID,
            NULLIF(TRIM(Title), '')                             AS Title,
            NULLIF(TRIM(First_Name), '')                        AS First_Name,
            NULLIF(TRIM(Middle_Name), '')                       AS Middle_Name,
            NULLIF(TRIM(Last_Name), '')                         AS Last_Name,
            NULLIF(CONCAT_WS(' ',
                NULLIF(TRIM(Title),''),
                NULLIF(TRIM(First_Name),''),
                NULLIF(TRIM(Middle_Name),''),
                NULLIF(TRIM(Last_Name),'')),'')                 AS Full_Name,
            NULLIF(TRIM(Email), '')                             AS Email,
            NULLIF(TRIM(Mobile_Phone), '')                      AS Mobile_Phone,
            NULLIF(TRIM(Role), '')                              AS Role,
            CAST(Permission_Level AS INT)                       AS Permission_Level,
            NULLIF(TRIM(Practice_ID), '')                       AS Practice_ID,
            NULLIF(TRIM(Site_ID), '')                           AS Site_ID,
            NULLIF(TRIM(Image_URL), '')                         AS Image_URL,
            TRY_CAST(NULLIF(TRIM(Last_Login),'') AS DATE)       AS Last_Login_Date,
            TRY_CAST(NULLIF(TRIM(Created_At),'') AS datetime2(3)) AS Created_Date,
            TRY_CAST(NULLIF(TRIM(Updated_At),'') AS datetime2(3)) AS Updated_Date,
            CAST(1 AS INT)                                        AS User_Count
        INTO #src
        FROM Silver.Users
        WHERE Id IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Users tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_User_ID = tgt.bk_User_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_User <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Title               = src.Title,
            First_Name          = src.First_Name,
            Middle_Name         = src.Middle_Name,
            Last_Name           = src.Last_Name,
            Full_Name           = src.Full_Name,
            Email               = src.Email,
            Mobile_Phone        = src.Mobile_Phone,
            Role                = src.Role,
            Permission_Level    = src.Permission_Level,
            Practice_ID         = src.Practice_ID,
            Site_ID             = src.Site_ID,
            Image_URL           = src.Image_URL,
            Last_Login_Date     = src.Last_Login_Date,
            Created_Date        = src.Created_Date,
            Updated_Date        = src.Updated_Date,
            DW_Updated_At       = SYSUTCDATETIME()
        FROM Gold.Dim_Users tgt
        INNER JOIN #src src ON tgt.bk_User_ID = src.bk_User_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Practice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Created_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Updated_Date] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Title] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[First_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Middle_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Full_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Email] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Mobile_Phone] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Role] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Permission_Level] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Practice_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Site_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Image_URL] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Last_Login_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Created_Date] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Updated_Date] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_User_base BIGINT = ISNULL((SELECT MAX(pk_User) FROM Gold.Dim_Users WHERE pk_User > 0), 0);
        INSERT INTO Gold.Dim_Users (
            pk_User,
            Tenant_ID,
            bk_User_ID, Title, First_Name, Middle_Name, Last_Name, Full_Name,
            Email, Mobile_Phone, Role, Permission_Level, Practice_ID, Site_ID,
            Image_URL, Last_Login_Date, Created_Date, Updated_Date,
            User_Count, DW_Created_At, DW_Updated_At, Is_Current
        )
        SELECT
            @pk_User_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.bk_User_ID),
            src.Tenant_ID,
            src.bk_User_ID, src.Title, src.First_Name, src.Middle_Name, src.Last_Name, src.Full_Name,
            src.Email, src.Mobile_Phone, src.Role, src.Permission_Level, src.Practice_ID, src.Site_ID,
            src.Image_URL, src.Last_Login_Date, src.Created_Date, src.Updated_Date,
            src.User_Count, SYSUTCDATETIME(), SYSUTCDATETIME(), 1
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Users tgt WHERE tgt.bk_User_ID = src.bk_User_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Users (pk_User, Tenant_ID, bk_User_ID, User_Count, DW_Created_At, DW_Updated_At, Is_Current)
        SELECT -1, -1, -1, 0, SYSUTCDATETIME(), SYSUTCDATETIME(), 0
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Users WHERE pk_User = -1);
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
