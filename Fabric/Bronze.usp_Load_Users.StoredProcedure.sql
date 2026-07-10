--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Users
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *03     19/05/2026  AIH Add title, middle_name, mobile_phone, site_id, created_at, updated_at, last_login
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Users @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Users]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Users]
(
      @Tenant_ID    INT
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT
              TRY_CAST(tenant_id AS INT)   AS Tenant_ID
            , TRY_CAST(id        AS INT)   AS ID
            , LEFT(first_name,   255)      AS First_Name
            , LEFT(last_name,    255)      AS Last_Name
            , LEFT(email,        255)      AS Email
            , LEFT(role,         255)      AS Role
            , LEFT(title,        255)      AS Title
            , LEFT(middle_name,  255)      AS Middle_Name
            , LEFT(mobile_phone, 255)      AS Mobile_Phone
            , LEFT(site_id,      255)      AS Site_ID
            , LEFT(created_at,   255)      AS Created_At
            , LEFT(updated_at,   255)      AS Updated_At
            , LEFT(last_login,   255)      AS Last_Login
        INTO #src
        FROM Stage.Users
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.First_Name   = src.First_Name
            , tgt.Last_Name    = src.Last_Name
            , tgt.Email        = src.Email
            , tgt.Role         = src.Role
            , tgt.Title        = src.Title
            , tgt.Middle_Name  = src.Middle_Name
            , tgt.Mobile_Phone = src.Mobile_Phone
            , tgt.Site_ID      = src.Site_ID
            , tgt.Created_At   = src.Created_At
            , tgt.Updated_At   = src.Updated_At
            , tgt.Last_Login   = src.Last_Login
            , tgt.DW_Loaded_At = SYSUTCDATETIME()
        FROM Bronze.Users AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Users (Tenant_ID, ID, First_Name, Last_Name, Email, Role, Title, Middle_Name, Mobile_Phone, Site_ID, Created_At, Updated_At, Last_Login, DW_Loaded_At)
        SELECT src.Tenant_ID, src.ID, src.First_Name, src.Last_Name, src.Email, src.Role, src.Title, src.Middle_Name, src.Mobile_Phone, src.Site_ID, src.Created_At, src.Updated_At, src.Last_Login, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Users tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.ID = src.ID);
        SET @My_Inserts = @@ROWCOUNT;


        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
