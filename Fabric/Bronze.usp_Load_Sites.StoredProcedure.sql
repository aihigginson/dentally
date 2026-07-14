--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Sites
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Map all Bronze.Sites columns (practice_id, active, opening hours etc.)
--    *03     16/05/2026  AIH Add Audit ETL logging (ETL_Start_Run / ETL_Finish_Run)
--    *04     19/05/2026  AIH Fix phone->phone_number Stage field name; add Email_Address, Nickname
--    *05     20/05/2026  AIH Default address_line_2/website/logo_url/default_payment_plan_id/email_address/nickname in gen_tenant() to ensure Stage columns always present
--    *06     02/06/2026  AIH Boolean columns stored raw (VARCHAR) in Bronze; cast moved to Silver
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_Sites]
GO
CREATE PROCEDURE [Bronze].[usp_Load_Sites]
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
              TRY_CAST(tenant_id        AS INT)                                                              AS Tenant_ID
            , LEFT(id,                     255)                                                              AS Site_ID
            , LEFT(practice_id,            255)                                                              AS Practice_ID
            , LEFT(name,                   255)                                                              AS Name
            , LEFT(active, 255)                                                                             AS Active
            , LEFT(address_line_1,         255)                                                              AS Address_Line_1
            , LEFT(address_line_2,         255)                                                              AS Address_Line_2
            , LEFT(town,                   255)                                                              AS Town
            , LEFT(postcode,               255)                                                              AS Postcode
            , LEFT(phone_number,            255)                                                              AS Phone_Number
            , LEFT(email_address,          255)                                                              AS Email_Address
            , LEFT(nickname,               255)                                                              AS Nickname
            , LEFT(website,                255)                                                              AS Website
            , LEFT(logo_url,               255)                                                              AS Logo_Url
            , TRY_CAST(default_payment_plan_id AS DECIMAL(18,4))                                            AS Default_Payment_Plan_ID
            , LEFT(monday_open,            255)                                                              AS Monday_Open
            , LEFT(monday_close,           255)                                                              AS Monday_Close
            , LEFT(tuesday_open,           255)                                                              AS Tuesday_Open
            , LEFT(tuesday_close,          255)                                                              AS Tuesday_Close
            , LEFT(wednesday_open,         255)                                                              AS Wednesday_Open
            , LEFT(wednesday_close,        255)                                                              AS Wednesday_Close
            , LEFT(thursday_open,          255)                                                              AS Thursday_Open
            , LEFT(thursday_close,         255)                                                              AS Thursday_Close
            , LEFT(friday_open,            255)                                                              AS Friday_Open
            , LEFT(friday_close,           255)                                                              AS Friday_Close
        INTO #src
        FROM Stage.Sites
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.Practice_ID              = src.Practice_ID
            , tgt.Name                     = src.Name
            , tgt.Active                   = src.Active
            , tgt.Address_Line_1           = src.Address_Line_1
            , tgt.Address_Line_2           = src.Address_Line_2
            , tgt.Town                     = src.Town
            , tgt.Postcode                 = src.Postcode
            , tgt.Phone_Number             = src.Phone_Number
            , tgt.Email_Address            = src.Email_Address
            , tgt.Nickname                 = src.Nickname
            , tgt.Website                  = src.Website
            , tgt.Logo_Url                 = src.Logo_Url
            , tgt.Default_Payment_Plan_ID  = src.Default_Payment_Plan_ID
            , tgt.Monday_Open              = src.Monday_Open
            , tgt.Monday_Close             = src.Monday_Close
            , tgt.Tuesday_Open             = src.Tuesday_Open
            , tgt.Tuesday_Close            = src.Tuesday_Close
            , tgt.Wednesday_Open           = src.Wednesday_Open
            , tgt.Wednesday_Close          = src.Wednesday_Close
            , tgt.Thursday_Open            = src.Thursday_Open
            , tgt.Thursday_Close           = src.Thursday_Close
            , tgt.Friday_Open              = src.Friday_Open
            , tgt.Friday_Close             = src.Friday_Close
            , tgt.DW_Loaded_At             = SYSUTCDATETIME()
        FROM Bronze.Sites AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Site_ID = src.Site_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Sites (Tenant_ID, Site_ID, Practice_ID, Name, Active, Address_Line_1, Address_Line_2, Town, Postcode, Phone_Number, Email_Address, Nickname, Website, Logo_Url, Default_Payment_Plan_ID, Monday_Open, Monday_Close, Tuesday_Open, Tuesday_Close, Wednesday_Open, Wednesday_Close, Thursday_Open, Thursday_Close, Friday_Open, Friday_Close, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Site_ID, src.Practice_ID, src.Name, src.Active, src.Address_Line_1, src.Address_Line_2, src.Town, src.Postcode, src.Phone_Number, src.Email_Address, src.Nickname, src.Website, src.Logo_Url, src.Default_Payment_Plan_ID, src.Monday_Open, src.Monday_Close, src.Tuesday_Open, src.Tuesday_Close, src.Wednesday_Open, src.Wednesday_Close, src.Thursday_Open, src.Thursday_Close, src.Friday_Open, src.Friday_Close, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Sites tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Site_ID = src.Site_ID);
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
