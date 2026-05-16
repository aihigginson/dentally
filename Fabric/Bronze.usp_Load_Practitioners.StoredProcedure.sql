--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_Practitioners] @Tenant_ID=1, @Full_Refresh=1, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_Practitioners
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     02/05/2026  AIH Add Practitioner_Active from Stage (JSON boolean → 1/0)
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
    , @Full_Refresh BIT    = 0
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
            , LEFT(first_name,    255)                                       AS User_First_Name
            , LEFT(last_name,     255)                                       AS User_Last_Name
            , LEFT(role,          255)                                       AS User_Role
            , LEFT(site_id,       255)                                       AS Practitioner_Site_ID
            , CASE WHEN LOWER(CAST(active AS VARCHAR(10))) = 'true'
                   THEN CAST(1.0 AS DECIMAL(18,4))
                   ELSE CAST(0.0 AS DECIMAL(18,4)) END                      AS Practitioner_Active
        INTO #src
        FROM Stage.Practitioners
        WHERE TRY_CAST(tenant_id AS INT) = @Tenant_ID;

        UPDATE tgt SET
              tgt.User_ID               = src.User_ID
            , tgt.User_First_Name       = src.User_First_Name
            , tgt.User_Last_Name        = src.User_Last_Name
            , tgt.User_Role             = src.User_Role
            , tgt.Practitioner_Site_ID  = src.Practitioner_Site_ID
            , tgt.Practitioner_Active   = src.Practitioner_Active
            , tgt.DW_Loaded_At          = SYSUTCDATETIME()
        FROM Bronze.Practitioners AS tgt
        INNER JOIN #src AS src ON tgt.Tenant_ID = src.Tenant_ID AND tgt.Practitioner_ID = src.Practitioner_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO Bronze.Practitioners (Tenant_ID, Practitioner_ID, User_ID, User_First_Name, User_Last_Name, User_Role, Practitioner_Site_ID, Practitioner_Active, DW_Loaded_At)
        SELECT src.Tenant_ID, src.Practitioner_ID, src.User_ID, src.User_First_Name, src.User_Last_Name, src.User_Role, src.Practitioner_Site_ID, src.Practitioner_Active, SYSUTCDATETIME()
        FROM #src AS src
        WHERE NOT EXISTS (SELECT 1 FROM Bronze.Practitioners tgt WHERE tgt.Tenant_ID = src.Tenant_ID AND tgt.Practitioner_ID = src.Practitioner_ID);
        SET @My_Inserts = @@ROWCOUNT;

        IF @Full_Refresh = 1
        BEGIN
            DELETE tgt FROM Bronze.Practitioners AS tgt
            WHERE tgt.Tenant_ID = @Tenant_ID
              AND NOT EXISTS (SELECT 1 FROM #src WHERE Practitioner_ID = tgt.Practitioner_ID);
            SET @My_Deletes = @@ROWCOUNT;
        END

        DROP TABLE IF EXISTS #src;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
