--------------------------------------------------------------------
--  AppDB.Migration.Top_Node.sql
--
--  Runs against the APPDB (sql-analytically.database.windows.net / AppDB-dev).
--
--  ==> IT DOES NOT NEED HANDING TO ANYONE. <== Scripts/appdb_run.py authenticates with the
--  owner's DELEGATED token (az account get-access-token) and connects as dbo -- db_owner and
--  db_ddladmin both. The "data rights only, no DDL" limit belongs to the APP's service principal,
--  which is a different identity, and conflating the two means handing back work that could just
--  be run. Same shape as the prod warehouse deploys: a delegated token, not a bypass.
--
--  ==> IT MUST RUN BEFORE THE WAREHOUSE SIDE. <== appdb_sync takes its column list from the
--  TARGET (Input_Stage), so adding the columns to the warehouse first makes the sync's source
--  SELECT name a column the AppDB does not have, and the sync starts failing. It reports
--  SUCCEEDED while failing, and nothing alerts on the container job, so that break would be
--  invisible for days. AppDB first, warehouse second.
--
--  WHAT THIS IS FOR -------------------------------------------------------------------
--  A user's TOP NODE: the highest point of the client hierarchy they may look at. It is the
--  default selection when they open a report, and the ceiling on what the hierarchy drop-down
--  will let them pick. A regional manager gets 'North' and sees North and below.
--
--  ==> IT IS NOT A SECURITY BOUNDARY, AND THAT IS DELIBERATE. <== RLS still grants the whole
--  client's data, because a report that compares an area against the GROUP mean cannot compute
--  the group mean from rows RLS has removed. The top node restricts what a user can navigate to,
--  not what the model holds. The boundary that carries commercial weight is cross-client, and
--  that stays RLS-enforced.
--
--  ==> STORED AS A STABLE KEY, NOT THE DROP-DOWN TEXT. <== The obvious thing is to store the
--  selection string the user picked. Don't: it contains the node's NAME, so renaming an area
--  would leave the stored value matching nothing. That fails closed -- the user silently loses
--  access, with no error raised anywhere, which is the worst kind of bug to diagnose. (Level,
--  Key) survives a rename, and Gold.Dim_Hierarchy_Node resolves it to the current text nightly.
--
--  NULL in both columns means "the client's root" -- everything. That is exactly today's
--  behaviour, so every existing user is unaffected and there is nothing to backfill.
--
--  Key by level:  Client -> Client_ID   Region -> Client_Region.Region_ID
--                 Area   -> Client_Area.Area_ID
--                 Practice -> Tenant_ID  Site -> Gold.Dim_Practice_Sites.pk_Practice_Site
--------------------------------------------------------------------

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Input.Application_Users') AND name = 'Top_Node_Level')
    ALTER TABLE [Input].[Application_Users] ADD [Top_Node_Level] VARCHAR(10) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('Input.Application_Users') AND name = 'Top_Node_Key')
    ALTER TABLE [Input].[Application_Users] ADD [Top_Node_Key] VARCHAR(64) NULL;
GO

-- Nothing to backfill: NULL already means the root. This only proves the columns arrived.
SELECT COUNT(*)                                                       AS users_total,
       SUM(CASE WHEN Top_Node_Level IS NULL THEN 1 ELSE 0 END)        AS at_the_root,
       SUM(CASE WHEN Top_Node_Level IS NOT NULL THEN 1 ELSE 0 END)    AS narrowed
FROM   [Input].[Application_Users];
GO
