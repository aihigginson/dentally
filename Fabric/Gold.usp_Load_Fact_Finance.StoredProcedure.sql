--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_Finance
--  Author           :  AIH
--  Initial Date     :  2026-07-01
--  History          :
--    *01     2026-07-01  AIH  Initial release (Xero profitability slice)
--  Notes            :  Full rebuild from Silver.Xero_Finance_Lines. Resolves fk_* via
--                      LEFT JOIN + ISNULL(...,-1). Demo has no tracking/site, so
--                      fk_Practice_Site = -1 for now (real orgs resolve from Tracking).
--  To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC Gold.usp_Load_Fact_Finance @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Finance]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Finance]
(
      @Mode         VARCHAR(100)     = 'TEST'
    , @Logging      SMALLINT         = 1
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

        DELETE FROM Gold.Fact_Finance;
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO Gold.Fact_Finance (Tenant_ID, fk_GL_Account, fk_Date, fk_Practice_Site, Source, Doc_Type, Doc_Number, PL_Group, Account_Class, Net_Amount, PL_Amount, DW_Created_At)
        SELECT
              l.Tenant_ID
            , ISNULL(d.pk_GL_Account, -1)  AS fk_GL_Account
            , ISNULL(dd.pk_Date, -1)       AS fk_Date
            , -1                           AS fk_Practice_Site   -- Demo has no tracking->site
            , l.Source, l.Doc_Type, l.Doc_Number, l.PL_Group, l.Account_Class
            , l.Net_Amount, l.PL_Amount, SYSUTCDATETIME()
        FROM Silver.Xero_Finance_Lines AS l
        LEFT JOIN Gold.Dim_GL_Account AS d
            ON d.bk_Account_ID = l.Account_ID AND d.Tenant_ID = l.Tenant_ID
        LEFT JOIN Gold.Dim_Date AS dd
            ON dd.Full_Date = l.Doc_Date;
        SET @My_Inserts = @@ROWCOUNT;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
