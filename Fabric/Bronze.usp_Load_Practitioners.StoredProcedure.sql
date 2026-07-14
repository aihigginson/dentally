--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Practitioners
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     02/05/2026  AIH Add Practitioner_Active from Stage (JSON boolean → 1/0)
--    *03     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *04     19/05/2026  AIH Add gdc_number, nhs_number, default_contract_id, colour, user_title, user_email, user_mobile_phone, user_middle_name, contract_targets_string, user dates/login; fix nested user field names (user_first_name etc.)
--    *05     20/05/2026  AIH Flatten user_* fields in generate_data.py so Stage has flat columns (not nested user struct)
--    *06     20/05/2026  AIH Column naming convention fixes (Practitioner_Gdc_Number -> Practitioner_GDC_Number)
--    *07     05/06/2026  AIH Accept '1' as truthy for active — Stage stores BIT as integer not string 'true'
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_Practitioners @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Practitioners]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Practitioners]
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
              TRY_CAST(tenant_id  AS INT)                                   AS Tenant_ID
            , TRY_CAST(id         AS INT)                                   AS Practitioner_ID
            , TRY_CAST(user_id    AS INT)                                   AS User_ID
            , LEFT(user_first_name,    255)                                  AS User_First_Name
            , LEFT(user_last_name,     255)                                  AS User_Last_Name
            , LEFT(user_role,          255)                                  AS User_Role
            , LEFT(user_title,         255)                                  AS User_Title
            , LEFT(user_email,         255)                                  AS User_Email
            , LEFT(user_mobile_phone,  255)                                  AS User_Mobile_Phone
            , LEFT(user_middle_name,   255)                                  AS User_Middle_Name
            , LEFT(user_image_url,     255)                                  AS User_Image_Url
            , LEFT(user_created_at,    255)                                  AS User_Created_At
            , LEFT(user_updated_at,    255)                                  AS User_Updated_At
            , LEFT(user_last_login,    255)                                  AS User_Last_Login
            , TRY_CAST(user_permission_level AS DECIMAL(18,4))               AS User_Permission_Level
            , LEFT(site_id,            255)                                  AS Practitioner_Site_ID
            , CASE WHEN LOWER(CAST(active AS VARCHAR(10))) IN ('true', '1')
                   THEN CAST(1.0 AS DECIMAL(18,4))
                   ELSE CAST(0.0 AS DECIMAL(18,4)) END                       AS Practitioner_Active
            , LEFT(gdc_number,         255)                                  AS Practitioner_GDC_Number
            , LEFT(nhs_number,         255)                                  AS Practitioner_NHS_Number
            , LEFT(default_contract_id,255)                                  AS Practitioner_Default_Contract_ID
            , LEFT(colour,             255)                                  AS Practitioner_Colour
            , CAST(contract_targets AS VARCHAR(MAX))                         AS Contract_Targets_String
        INTO #src
        FROM Stage.Practitioners
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.User_ID                        = src.User_ID
            , tgt.User_First_Name                = src.User_First_Name
            , tgt.User_Last_Name                 = src.User_Last_Name
            , tgt.User_Role                      = src.User_Role
            , tgt.User_Title                     = src.User_Title
            , tgt.User_Email                     = src.User_Email
            , tgt.User_Mobile_Phone              = src.User_Mobile_Phone
            , tgt.User_Middle_Name               = src.User_Middle_Name
            , tgt.User_Image_Url                 = src.User_Image_Url
            , tgt.User_Created_At                = src.User_Created_At
            , tgt.User_Updated_At                = src.User_Updated_At
            , tgt.User_Last_Login                = src.User_Last_Login
            , tgt.User_Permission_Level          = src.User_Permission_Level
            , tgt.Practitioner_Site_ID           = src.Practitioner_Site_ID
            , tgt.Practitioner_Active            = src.Practitioner_Active
            , tgt.Practitioner_GDC_Number        = src.Practitioner_GDC_Number
            , tgt.Practitioner_NHS_Number        = src.Practitioner_NHS_Number
            , tgt.Practitioner_Default_Contract_ID = src.Practitioner_Default_Contract_ID
            , tgt.Practitioner_Colour            = src.Practitioner_Colour
            , tgt.Contract_Targets_String        = src.Contract_Targets_String
            , tgt.DW_Loaded_At                   = SYSUTCDATETIME()
        FROM Bronze.Practitioners AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Practitioner_ID = src.Practitioner_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Practitioners (Tenant_ID, Practitioner_ID, User_ID, User_First_Name, User_Last_Name, User_Role, User_Title, User_Email, User_Mobile_Phone, User_Middle_Name, User_Image_Url, User_Created_At, User_Updated_At, User_Last_Login, User_Permission_Level, Practitioner_Site_ID, Practitioner_Active, Practitioner_GDC_Number, Practitioner_NHS_Number, Practitioner_Default_Contract_ID, Practitioner_Colour, Contract_Targets_String, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Practitioner_ID, src.User_ID, src.User_First_Name, src.User_Last_Name, src.User_Role, src.User_Title, src.User_Email, src.User_Mobile_Phone, src.User_Middle_Name, src.User_Image_Url, src.User_Created_At, src.User_Updated_At, src.User_Last_Login, src.User_Permission_Level, src.Practitioner_Site_ID, src.Practitioner_Active, src.Practitioner_GDC_Number, src.Practitioner_NHS_Number, src.Practitioner_Default_Contract_ID, src.Practitioner_Colour, src.Contract_Targets_String, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Practitioners tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Practitioner_ID = src.Practitioner_ID);
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
