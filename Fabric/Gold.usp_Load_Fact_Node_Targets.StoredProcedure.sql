--------------------------------------------------------------------
--  Procedure : Gold.usp_Load_Fact_Node_Targets
--  Author    : AIH
--  Date      : 29/10/2026
--
--  EXPLODE THE SPARSE TARGET GRID ACROSS EVERY NODE OF EVERY CLIENT'S HIERARCHY.
--
--  Input.Targets holds only what somebody TYPED -- one row per (node, FY, metric, role). This
--  produces the other thing: one row for every node that should have a target, whether it was
--  entered or derived. Downstream (daily apportionment, period aggregation, DAX) then never has
--  to know which it was, and the roll-up rules live HERE, in SQL, where a query can check them,
--  rather than in DAX where they cannot.
--
--  ==> IT IS KEYED ON THE CLIENT, NOT THE TENANT. <== A Region or Area target spans tenants and
--  has no single Tenant_ID to carry; forcing one would mean either duplicating the row per tenant
--  (and inviting a SUM that double counts) or parking it on the -1 sentinel (which the RLS escape
--  would then expose to every other client). Client_ID is what the node actually belongs to.
--  Tenant_ID is carried as well, but only where the node HAS one -- Practice and Site -- and is
--  NULL above that, which is the honest answer rather than a filled-in guess.
--
--  ==> WHICH WAY A TARGET TRAVELS IS Config.Metric_Definitions.Rolls_Up, AND NOTHING ELSE. <==
--      1 = a QUANTITY. A node with no target of its own is the SUM of its children. Revenue,
--          patient counts, outstanding invoices.
--      0 = a RATE. A node with no target of its own inherits its PARENT'S. A DNA rate does not
--          get bigger because a group has more sites.
--  An entered target always wins over a derived one, at every level.
--
--  ==> A PARTIAL ROLL-UP IS SIMPLY WRONG, AND THAT IS ACCEPTED. <== If an area holds three
--  practices and only two have targets, the area reads the sum of those two. It is not scaled up,
--  not pro-rated, and not suppressed. The owner's rule: enter the third, or enter the area's own
--  figure. Inventing a number for the missing practice would be a guess wearing a target's
--  clothes, and nobody would know it had happened.
--
--  Pattern: full DELETE + INSERT. The grid is small (nodes x metrics x roles x FY) and entirely
--  derived, so there is nothing to preserve and incremental logic would only add ways to be stale.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Node_Targets]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Node_Targets]
(
      @Mode        VARCHAR(100)     = 'TEST'
    , @Logging     SMALLINT         = 1
    , @Run_UUID    UNIQUEIDENTIFIER = NULL
    , @Run_Inserts BIGINT OUT
    , @Run_Updates BIGINT OUT
    , @Run_Deletes BIGINT OUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;

    BEGIN TRY

        ---------------------------------------------------------------- 1. the tree
        -- Every node, with its parent. Practice sits between Area and Site because a tenant's
        -- sites all hang off one area today; a tenant that ever spans areas breaks this join
        -- rather than silently mis-parenting, which is the failure mode to prefer.
        DROP TABLE IF EXISTS #nodes;
        SELECT Level_Type, Level_Key, Client_ID, Parent_Type, Parent_Key, Tenant_ID
        INTO   #nodes
        FROM (
            SELECT CAST('Group' AS VARCHAR(10)) AS Level_Type,
                   CAST(c.Client_ID AS VARCHAR(64)) AS Level_Key, c.Client_ID,
                   CAST(NULL AS VARCHAR(10)) AS Parent_Type, CAST(NULL AS VARCHAR(64)) AS Parent_Key,
                   CAST(NULL AS INT) AS Tenant_ID
            FROM   [Input].[Client] c
            UNION ALL
            SELECT 'Region', CAST(r.Region_ID AS VARCHAR(64)), r.Client_ID,
                   'Group', CAST(r.Client_ID AS VARCHAR(64)), NULL
            FROM   [Input].[Client_Region] r
            UNION ALL
            SELECT 'Area', CAST(a.Area_ID AS VARCHAR(64)), r.Client_ID,
                   'Region', CAST(a.Region_ID AS VARCHAR(64)), NULL
            FROM   [Input].[Client_Area] a
            JOIN   [Input].[Client_Region] r ON r.Region_ID = a.Region_ID
            UNION ALL
            SELECT DISTINCT 'Practice', CAST(sa.Tenant_ID AS VARCHAR(64)), r.Client_ID,
                   'Area', CAST(sa.Area_ID AS VARCHAR(64)), sa.Tenant_ID
            FROM   [Input].[Site_Area] sa
            JOIN   [Input].[Client_Area] a ON a.Area_ID = sa.Area_ID
            JOIN   [Input].[Client_Region] r ON r.Region_ID = a.Region_ID
            UNION ALL
            SELECT 'Site', CAST(sa.Site_ID AS VARCHAR(64)), r.Client_ID,
                   'Practice', CAST(sa.Tenant_ID AS VARCHAR(64)), sa.Tenant_ID
            FROM   [Input].[Site_Area] sa
            JOIN   [Input].[Client_Area] a ON a.Area_ID = sa.Area_ID
            JOIN   [Input].[Client_Region] r ON r.Region_ID = a.Region_ID
        ) n;

        ---------------------------------------------------------------- 2. what was typed
        -- Joined to the tree, so a target naming a node that no longer exists (an area deleted
        -- after the target was set) drops out HERE rather than becoming an orphan row nothing
        -- can ever select.
        DROP TABLE IF EXISTS #res;
        SELECT n.Client_ID, n.Level_Type, n.Level_Key, n.Tenant_ID,
               t.FY, t.Metric, t.Target_Level,
               CAST(t.Target_Value AS DECIMAL(18,4)) AS Target_Value,
               CAST(1 AS BIT) AS Is_Entered
        INTO   #res
        FROM   [Input].[Targets] t
        JOIN   #nodes n ON n.Level_Type = t.Level_Type AND n.Level_Key = t.Level_Key;

        ---------------------------------------------------------------- 3. quantities roll UP
        -- Four passes, child level to parent. A node already holding a value -- entered, or
        -- summed on an earlier pass -- is never overwritten, so an entered figure at any level
        -- stops the roll there and becomes the truth for everything above it.
        DECLARE @child VARCHAR(10), @i INT = 0;
        WHILE @i < 4
        BEGIN
            SET @child = CASE @i WHEN 0 THEN 'Site' WHEN 1 THEN 'Practice'
                                 WHEN 2 THEN 'Area' ELSE 'Region' END;

            INSERT INTO #res (Client_ID, Level_Type, Level_Key, Tenant_ID, FY, Metric, Target_Level,
                              Target_Value, Is_Entered)
            SELECT p.Client_ID, p.Level_Type, p.Level_Key, p.Tenant_ID,
                   r.FY, r.Metric, r.Target_Level,
                   CAST(SUM(r.Target_Value) AS DECIMAL(18,4)), 0
            FROM   #res r
            JOIN   #nodes cn ON cn.Level_Type = r.Level_Type AND cn.Level_Key = r.Level_Key
            JOIN   #nodes p  ON p.Level_Type  = cn.Parent_Type AND p.Level_Key = cn.Parent_Key
            JOIN   [Config].[Metric_Definitions] md ON md.Metric_Key = r.Metric AND md.Rolls_Up = 1
            WHERE  cn.Level_Type = @child
              AND  NOT EXISTS (SELECT 1 FROM #res x
                               WHERE x.Level_Type = p.Level_Type AND x.Level_Key = p.Level_Key
                                 AND x.FY = r.FY AND x.Metric = r.Metric
                                 AND x.Target_Level = r.Target_Level)
            GROUP BY p.Client_ID, p.Level_Type, p.Level_Key, p.Tenant_ID,
                     r.FY, r.Metric, r.Target_Level;

            SET @i = @i + 1;
        END

        ---------------------------------------------------------------- 4. rates roll DOWN
        -- Four passes, parent to child, the other way along the same tree.
        DECLARE @parent VARCHAR(10);
        SET @i = 0;
        WHILE @i < 4
        BEGIN
            SET @parent = CASE @i WHEN 0 THEN 'Group' WHEN 1 THEN 'Region'
                                  WHEN 2 THEN 'Area' ELSE 'Practice' END;

            INSERT INTO #res (Client_ID, Level_Type, Level_Key, Tenant_ID, FY, Metric, Target_Level,
                              Target_Value, Is_Entered)
            SELECT cn.Client_ID, cn.Level_Type, cn.Level_Key, cn.Tenant_ID,
                   r.FY, r.Metric, r.Target_Level, r.Target_Value, 0
            FROM   #res r
            JOIN   #nodes cn ON cn.Parent_Type = r.Level_Type AND cn.Parent_Key = r.Level_Key
            JOIN   [Config].[Metric_Definitions] md ON md.Metric_Key = r.Metric AND md.Rolls_Up = 0
            WHERE  r.Level_Type = @parent
              AND  NOT EXISTS (SELECT 1 FROM #res x
                               WHERE x.Level_Type = cn.Level_Type AND x.Level_Key = cn.Level_Key
                                 AND x.FY = r.FY AND x.Metric = r.Metric
                                 AND x.Target_Level = r.Target_Level);

            SET @i = @i + 1;
        END

        ---------------------------------------------------------------- 5. publish
        DELETE FROM [Gold].[Fact_Node_Targets];
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Gold].[Fact_Node_Targets]
            (pk_Node_Target, Client_ID, Level_Type, Level_Key, Tenant_ID, FY, Metric,
             Target_Level, Target_Value, Is_Entered, DW_Created_At)
        SELECT ROW_NUMBER() OVER (ORDER BY Client_ID, Level_Type, Level_Key, FY, Metric, Target_Level),
               Client_ID, Level_Type, Level_Key, Tenant_ID, FY, Metric, Target_Level,
               Target_Value, Is_Entered, SYSUTCDATETIME()
        FROM   #res;
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE IF EXISTS #nodes; DROP TABLE IF EXISTS #res;

        SET @Run_Inserts = @My_Inserts; SET @Run_Updates = @My_Updates; SET @Run_Deletes = @My_Deletes;

        IF @Logging = 1
            EXEC [Audit].[ETL_Log_Record_Counts] @Run_UUID = @Run_UUID,
                 @Process_Name = 'Gold.usp_Load_Fact_Node_Targets',
                 @Table_Name = 'Gold.Fact_Node_Targets',
                 @Rows_Inserted = @My_Inserts, @Rows_Updated = @My_Updates, @Rows_Deleted = @My_Deletes;
    END TRY
    BEGIN CATCH
        EXEC [Audit].[ETL_Error_Handler] @Run_UUID = @Run_UUID,
             @Process_Name = 'Gold.usp_Load_Fact_Node_Targets';
        THROW;
    END CATCH
END
GO
