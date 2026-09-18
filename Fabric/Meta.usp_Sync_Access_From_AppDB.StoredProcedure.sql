--DECLARE @i BIGINT,@u BIGINT,@d BIGINT; EXEC [Meta].[usp_Sync_Access_From_AppDB] @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
-----------------------------------------------------------------------------------------------------
--    Stored Procedure : Meta.usp_Sync_Access_From_AppDB
--    Author           : AIH
--    History          :
--        *01  17/07/2026  AIH  Frequent (10-min) sync of ONLY the subscription access data from AppDB
--                              -> WH.Security.* . Split out of usp_Sync_Input_From_AppDB so it can run
--                              on a short schedule without re-doing the full Input.* refresh (which
--                              would race the nightly build's fact loads). UPSERT only -- auth rows are
--                              never wiped; a removal arrives as no_access (all module flags 0).
--        *02  28/07/2026  AIH  Security holds ACCESS-HOLDERS ONLY. A user with no module AND no admin
--                              (Maintain_Targets) gets NO Security row: never inserted, and a downgrade
--                              to no-access DELETEs the existing row. Input keeps the full record (the
--                              Team screen reads it); Security is the auth/reporting surface, so it is
--                              no longer cluttered with all-zero no-access rows. Supersedes *01's
--                              "removal = no_access row" note.
--        *03  17/09/2026  AIH  Read [Input_Stage].* instead of [AppDB].[Input].*. AppDB has moved
--                              off the Fabric capacity to Azure SQL (AppDB/MIGRATION.md), and a
--                              three-part name only resolves for a Fabric item in the SAME
--                              workspace -- so the cross-DB read could no longer reach it. The
--                              appdb-sync Container Apps Job lands the rows in Input_Stage first.
--                              MERGE logic is UNCHANGED: staging was verified row-for-row identical
--                              to the old source (EXCEPT zero both ways) before this switch, so the
--                              proc sees exactly what it saw before.
--    To Run           :  DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--                        EXEC Meta.usp_Sync_Access_From_AppDB @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT;
-----------------------------------------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP PROCEDURE IF EXISTS [Meta].[usp_Sync_Access_From_AppDB]
GO
CREATE PROCEDURE [Meta].[usp_Sync_Access_From_AppDB]
(
      @Mode           VARCHAR(100)     = 'TEST'
    , @Logging        smallint         = 1
    , @Run_UUID       UNIQUEIDENTIFIER = NULL
    , @Run_Inserts    BIGINT   OUT
    , @Run_Updates    BIGINT   OUT
    , @Run_Deletes    BIGINT   OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        -- Application_Users (Subscriptions): UPSERT AppDB -> WH auth table. Security = ACCESS-HOLDERS ONLY.
        -- (*02) First REVOKE: delete any Security row whose AppDB row now has no module + no admin.
        DELETE tgt
        FROM [Security].[Application_Users] tgt
        JOIN [Input_Stage].[Application_Users] src ON LOWER(tgt.User_UPN) = LOWER(src.User_UPN)
        WHERE (EXISTS (
                     -- Deactivated in Dentally. The SAME expression the Subscriptions roster uses
                     -- (COALESCE(u.Permission_Level, sp.perm, 1) > 0), so the screen and billing
                     -- agree by construction rather than by coincidence -- they disagreeing is what
                     -- left Kelly Edge billed at front_office while invisible on the roster.
                     --
                     -- NOTE THE JOIN: only a user who HAS a Dim_Users row reading 0 is revoked.
                     -- Absence is NOT deactivation. A failed or part-loaded Dim_Users would
                     -- otherwise revoke the entire practice's access in one run, and the
                     -- COALESCE default of 1 likewise keeps a NULL Permission_Level (every row
                     -- before the Bronze.usp_Load_Users *04 backfill) meaning "assume active".
                     SELECT 1
                     FROM [Gold].[Dim_Users] du
                     LEFT JOIN (SELECT Tenant_ID, User_ID, MAX(User_Permission_Level) AS perm
                                FROM [Silver].[Practitioners] GROUP BY Tenant_ID, User_ID) sp
                            ON sp.Tenant_ID = du.Tenant_ID AND sp.User_ID = du.bk_User_ID
                     JOIN [Audit].[Tenants] dt ON dt.Tenant_ID = du.Tenant_ID
                     WHERE du.Is_Current = 1
                       AND LOWER(LTRIM(RTRIM(du.Email))) = LOWER(LTRIM(RTRIM(src.User_UPN)))
                       AND dt.Client_ID = src.Client_ID
                       AND COALESCE(du.Permission_Level, sp.perm, 1) = 0
                 )
           OR NOT (src.Access_Home=1 OR src.Access_Revenue=1 OR src.Access_Patient=1 OR src.Access_Schedule=1
               OR src.Access_Clinical=1 OR src.Access_NHS=1 OR src.Access_Day_Book=1 OR src.Access_Finance=1
               OR src.Access_My_Data=1 OR src.Access_Marketing=1 OR src.Maintain_Targets=1));
        SET @My_Deletes = @My_Deletes + @@ROWCOUNT;

        UPDATE tgt SET tgt.Client_ID=src.Client_ID, tgt.Display_Name=src.Display_Name, tgt.Maintain_Targets=src.Maintain_Targets,
            tgt.Access_Home=src.Access_Home, tgt.Access_Revenue=src.Access_Revenue, tgt.Access_Patient=src.Access_Patient,
            tgt.Access_Schedule=src.Access_Schedule, tgt.Access_Clinical=src.Access_Clinical, tgt.Access_NHS=src.Access_NHS,
            tgt.Access_Day_Book=src.Access_Day_Book, tgt.Access_Finance=src.Access_Finance, tgt.Access_My_Data=src.Access_My_Data,
            tgt.Access_Marketing=src.Access_Marketing, tgt.Practitioner_Full_Name=src.Practitioner_Full_Name, tgt.Profile_Key=src.Profile_Key
        FROM [Security].[Application_Users] tgt
        JOIN [Input_Stage].[Application_Users] src ON LOWER(tgt.User_UPN) = LOWER(src.User_UPN);
        SET @My_Updates = @My_Updates + @@ROWCOUNT;

        INSERT INTO [Security].[Application_Users] (User_UPN, Client_ID, Display_Name, Maintain_Targets, Access_Home, Access_Revenue, Access_Patient, Access_Schedule, Access_Clinical, Access_NHS, Access_Day_Book, Access_Finance, Access_My_Data, Access_Marketing, Practitioner_Full_Name, Profile_Key)
        SELECT src.User_UPN, src.Client_ID, src.Display_Name, src.Maintain_Targets, src.Access_Home, src.Access_Revenue, src.Access_Patient, src.Access_Schedule, src.Access_Clinical, src.Access_NHS, src.Access_Day_Book, src.Access_Finance, src.Access_My_Data, src.Access_Marketing, src.Practitioner_Full_Name, src.Profile_Key
        FROM [Input_Stage].[Application_Users] src
        LEFT JOIN [Security].[Application_Users] tgt ON LOWER(tgt.User_UPN) = LOWER(src.User_UPN)
        WHERE tgt.User_UPN IS NULL
          AND (src.Access_Home=1 OR src.Access_Revenue=1 OR src.Access_Patient=1 OR src.Access_Schedule=1
               OR src.Access_Clinical=1 OR src.Access_NHS=1 OR src.Access_Day_Book=1 OR src.Access_Finance=1
               OR src.Access_My_Data=1 OR src.Access_Marketing=1 OR src.Maintain_Targets=1)
          AND NOT EXISTS (
                     -- Deactivated in Dentally. The SAME expression the Subscriptions roster uses
                     -- (COALESCE(u.Permission_Level, sp.perm, 1) > 0), so the screen and billing
                     -- agree by construction rather than by coincidence -- they disagreeing is what
                     -- left Kelly Edge billed at front_office while invisible on the roster.
                     --
                     -- NOTE THE JOIN: only a user who HAS a Dim_Users row reading 0 is revoked.
                     -- Absence is NOT deactivation. A failed or part-loaded Dim_Users would
                     -- otherwise revoke the entire practice's access in one run, and the
                     -- COALESCE default of 1 likewise keeps a NULL Permission_Level (every row
                     -- before the Bronze.usp_Load_Users *04 backfill) meaning "assume active".
                     SELECT 1
                     FROM [Gold].[Dim_Users] du
                     LEFT JOIN (SELECT Tenant_ID, User_ID, MAX(User_Permission_Level) AS perm
                                FROM [Silver].[Practitioners] GROUP BY Tenant_ID, User_ID) sp
                            ON sp.Tenant_ID = du.Tenant_ID AND sp.User_ID = du.bk_User_ID
                     JOIN [Audit].[Tenants] dt ON dt.Tenant_ID = du.Tenant_ID
                     WHERE du.Is_Current = 1
                       AND LOWER(LTRIM(RTRIM(du.Email))) = LOWER(LTRIM(RTRIM(src.User_UPN)))
                       AND dt.Client_ID = src.Client_ID
                       AND COALESCE(du.Permission_Level, sp.perm, 1) = 0
                 );  -- access-holders only (*02)
        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;

        -- Access_Log: append rows not already in the warehouse (natural key).
        INSERT INTO [Security].[Access_Log] (Tenant_ID, User_UPN, Profile_Key, Effective_At, Changed_By)
        SELECT src.Tenant_ID, src.User_UPN, src.Profile_Key, src.Effective_At, src.Changed_By
        FROM [Input_Stage].[Access_Log] src
        LEFT JOIN [Security].[Access_Log] tgt ON tgt.User_UPN = src.User_UPN AND tgt.Effective_At = src.Effective_At AND tgt.Profile_Key = src.Profile_Key
        WHERE tgt.User_UPN IS NULL;
        SET @My_Inserts = @My_Inserts + @@ROWCOUNT;
    END TRY
    BEGIN CATCH
        ;THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts;
    SET @Run_Updates = @My_Updates;
    SET @Run_Deletes = @My_Deletes;
END
GO
