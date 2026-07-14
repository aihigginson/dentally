--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Accounts] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Accounts
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     01/05/2026  AIH Add -1 unknown seed row; protect from DELETE
--    *03     01/05/2026  AIH Remove IDENTITY from pk; use ROW_NUMBER for inserts; plain INSERT for -1 seed
--    *04     09/05/2026  AIH Filter Patient_Id IS NOT NULL — accounts without a patient are invalid
--    *05     20/05/2026  AIH Column naming convention fixes (ID/_ID, NHS)
--    *06     22/05/2026  AIH Add Account_Count (1 real, 0 sentinel) for SUM-based measures
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Gold.usp_Load_Dim_Accounts @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Dim_Accounts]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Accounts]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Accounts]
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
            Tenant_ID AS Tenant_ID,
            CAST(Account_ID AS INT)                                                  AS Account_ID,
            CAST(Patient_ID AS INT)                                                  AS Patient_ID,
            NULLIF(TRIM(Patient_Name),'')                                            AS Patient_Name,
            CAST(ISNULL(Current_Balance,0) AS DECIMAL(18,4))                        AS Current_Balance,
            CAST(ISNULL(Opening_Balance,0) AS DECIMAL(18,4))                        AS Opening_Balance,
            CAST(ISNULL(Planned_NHS_Treatment_Value,0) AS DECIMAL(18,4))            AS Planned_NHS_Treatment_Value,
            CAST(ISNULL(Planned_Private_Treatment_Value,0) AS DECIMAL(18,4))        AS Planned_Private_Treatment_Value,
            CAST(1 AS INT)                                                                                   AS Account_Count
        INTO #src
        FROM Silver.Accounts
        WHERE Account_ID IS NOT NULL
          AND Patient_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Dim_Accounts tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE Account_ID = tgt.Account_ID AND Tenant_ID = tgt.Tenant_ID)
        AND tgt.pk_Account <> -1;
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            Patient_ID                      = src.Patient_ID,
            Patient_Name                    = src.Patient_Name,
            Current_Balance                 = src.Current_Balance,
            Opening_Balance                 = src.Opening_Balance,
            Planned_NHS_Treatment_Value     = src.Planned_NHS_Treatment_Value,
            Planned_Private_Treatment_Value = src.Planned_Private_Treatment_Value,
            DW_Updated_At                   = SYSUTCDATETIME()
        FROM Gold.Dim_Accounts tgt
        INNER JOIN #src src ON tgt.Account_ID = src.Account_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[Patient_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Current_Balance] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Opening_Balance] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Planned_NHS_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Planned_Private_Treatment_Value] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[Patient_ID] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Name] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Current_Balance] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Opening_Balance] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Planned_NHS_Treatment_Value] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Planned_Private_Treatment_Value] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        DECLARE @pk_Account_base BIGINT = ISNULL((SELECT MAX(pk_Account) FROM Gold.Dim_Accounts WHERE pk_Account > 0), 0);
        INSERT INTO Gold.Dim_Accounts (
            pk_Account,
            Tenant_ID, Account_ID, Patient_ID, Patient_Name, Current_Balance, Opening_Balance,
            Planned_NHS_Treatment_Value, Planned_Private_Treatment_Value, Account_Count, DW_Created_At, DW_Updated_At
        )
        SELECT
            @pk_Account_base + ROW_NUMBER() OVER (ORDER BY src.Tenant_ID, src.Account_ID),
            src.Tenant_ID, src.Account_ID, src.Patient_ID, src.Patient_Name, src.Current_Balance, src.Opening_Balance,
            src.Planned_NHS_Treatment_Value, src.Planned_Private_Treatment_Value, src.Account_Count, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Accounts tgt WHERE tgt.Account_ID = src.Account_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        -- Ensure unknown/-1 seed row exists (Tenant_ID = -1 passes RLS for shared data)
        INSERT INTO Gold.Dim_Accounts (pk_Account, Tenant_ID, Account_ID, Account_Count, DW_Created_At, DW_Updated_At)
        SELECT -1, -1, -1, 0, SYSUTCDATETIME(), SYSUTCDATETIME()
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Dim_Accounts WHERE pk_Account = -1);
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
