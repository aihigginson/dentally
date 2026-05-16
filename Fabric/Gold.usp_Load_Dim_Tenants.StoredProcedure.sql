--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Tenants] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Tenants
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Tenants @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Tenants]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Tenants]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
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
            CAST(Tenant_ID   AS INT)         AS Tenant_ID,
            NULLIF(TRIM(Tenant_Name), '')    AS Tenant_Name,
            CAST(CASE WHEN Is_Active = 1 THEN 1 ELSE 0 END AS BIT) AS Is_Active
        INTO #src
        FROM Audit.Tenants
        WHERE Tenant_ID IS NOT NULL;

        DELETE tgt
        FROM Gold.Dim_Tenants tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Tenant <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        UPDATE tgt SET
            Tenant_Name   = src.Tenant_Name,
            Is_Active     = src.Is_Active,
            DW_Updated_At = SYSUTCDATETIME()
        FROM Gold.Dim_Tenants tgt
        INNER JOIN #src src ON tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(tgt.Tenant_Name AS VARCHAR(500)), ''),
            ISNULL(CAST(tgt.Is_Active   AS VARCHAR(500)), '')
            ))
            <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
            ISNULL(CAST(src.Tenant_Name AS VARCHAR(500)), ''),
            ISNULL(CAST(src.Is_Active   AS VARCHAR(500)), '')
            ));
        SET @My_Updates = @@ROWCOUNT;

        DECLARE @pk_Tenant_base BIGINT = ISNULL((SELECT MAX(pk_Tenant) FROM Gold.Dim_Tenants WHERE pk_Tenant > 0), 0);
        INSERT INTO Gold.Dim_Tenants (pk_Tenant, Tenant_ID, Tenant_Name, Is_Active, DW_Created_At, DW_Updated_At)
        SELECT
            @pk_Tenant_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID),
            src.Tenant_ID, src.Tenant_Name, src.Is_Active, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Tenants tgt WHERE tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Tenants (pk_Tenant, Tenant_ID, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Tenants WHERE pk_Tenant = -1);

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
