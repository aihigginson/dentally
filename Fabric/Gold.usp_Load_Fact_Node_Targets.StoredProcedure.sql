--------------------------------------------------------------------
--  Procedure : Gold.usp_Load_Fact_Node_Targets
--  Author    : AIH
--  History   :
--    *01  29/10/2026  AIH  Explode the sparse grid across every node of the hierarchy.
--    *02  29/10/2026  AIH  Keyed on the DROP-DOWN TEXT. Level_Type/Level_Key/Tenant_ID gone.
--
--  EXPLODE THE SPARSE TARGET GRID ACROSS THE HIERARCHY, KEYED ON WHAT THE USER PICKED.
--
--  Input.Targets holds only what somebody typed. This builds, for every selectable node, the
--  target in force there -- entered, rolled up from children, or rolled down from a parent --
--  and publishes it against the EXACT STRING the hierarchy drop-down shows.
--
--  ==> THE OUTPUT CARRIES NO HIERARCHY AT ALL. <== The tree is built here, used to roll values,
--  and thrown away. The published row says "client 20, '<indent>- Skeleton Alpha', All Roles,
--  total_revenue, FY2027, 1800000, entered" and nothing else, because that is all a reader or a
--  filter needs: the app sets [Selection] = the value the user chose. No level, no key, no
--  tenant, nothing to resolve or join. The previous revision stored Level_Type + Level_Key and
--  it was both unreadable and wrong -- the keys collided across levels, and Site held the
--  Dentally business key while every report filters the warehouse surrogate.
--
--  ==> A LEVEL THAT OFFERS NO CHOICE IS NOT BUILT. <== Exactly the test /api/filters applies:
--  a level with one distinct value across the client cannot narrow anything, so it is omitted
--  and the ones below it move up. Maple has one region, one area, one practice and one site, so
--  it gets ONE node -- its own name -- instead of five identical copies of every target. That
--  was 925 unreachable rows, and they were not merely waste: no measure filters a node, so five
--  copies of a target are summed or maxed into a figure five times too big.
--
--  ==> THE INDENT IS PART OF THE KEY, WHICH IS WHY IT IS BUILT FROM BYTES. <== The string must
--  match index.html byte for byte -- ' '.repeat(depth*2) + '- ' + label, with U+2007 FIGURE
--  SPACE and U+2013 EN DASH -- and Fabric's collation is binary, so a lookalike character would
--  silently match nothing. CAST(0xE28087 ...) cannot be altered by this file's own encoding,
--  which a literal character could be.
--
--  It also makes the text unique without a level column: client 11 has a PRACTICE and a SITE
--  both called "Demonstration Practice", and the client itself is called that too. They differ
--  here by nothing except the indent -- none, six figure spaces, eight -- and that is enough.
--
--  ==> ROLES ROLL DOWN ONLY. <== A role target is per-FTE (the measures multiply it by the FTE
--  in context), so it never sums upward: three practices each targeting 300k per dentist does
--  not make 900k per dentist at the group. Owner's rule: no roll up, roll down only. The
--  practice-wide figure ('All Roles') is the one that rolls up, and only when
--  Config.Metric_Definitions.Rolls_Up says the metric is a quantity.
--
--  It also publishes Gold.Dim_Hierarchy_Node -- selection -> the sites it covers -- because the
--  tree is in scope here and nothing else should rebuild it.
--
--  To Run: DECLARE @i BIGINT,@u BIGINT,@d BIGINT;
--          EXEC Gold.usp_Load_Fact_Node_Targets @Run_Inserts=@i OUT,@Run_Updates=@u OUT,@Run_Deletes=@d OUT
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
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        -- U+2007 FIGURE SPACE and U+2013 EN DASH, from their UTF-8 bytes. See the header.
        DECLARE @FIG VARCHAR(3) = CAST(0xE28087 AS VARCHAR(3));
        DECLARE @DSH VARCHAR(3) = CAST(0xE28093 AS VARCHAR(3));

        ---------------------------------------------------------------- 1. the hierarchy, flat
        -- One row per ACTIVE site with every ancestor it has. Same join /api/filters uses, minus
        -- its restriction to the signed-in user's tenants: the grid is built for the whole client.
        DROP TABLE IF EXISTS #h;
        SELECT r.Client_ID,
               CAST(r.Region_ID  AS VARCHAR(64)) AS Region_Key,
               CAST(r.Region_Name AS VARCHAR(200)) AS Region_Name,
               CAST(a.Area_ID    AS VARCHAR(64)) AS Area_Key,
               CAST(a.Area_Name  AS VARCHAR(200)) AS Area_Name,
               CAST(sa.Tenant_ID AS VARCHAR(64)) AS Practice_Key,
               CAST(t.Tenant_Name AS VARCHAR(200)) AS Practice_Name,
               CAST(s.pk_Practice_Site AS VARCHAR(64)) AS Site_Key,
               CAST(s.Site_Name  AS VARCHAR(200)) AS Site_Name,
               s.pk_Practice_Site, sa.Tenant_ID
        INTO   #h
        FROM   [Input].[Client_Region] r
        JOIN   [Input].[Client_Area]   a  ON a.Region_ID = r.Region_ID
        JOIN   [Input].[Site_Area]     sa ON sa.Area_ID  = a.Area_ID
        JOIN   [Gold].[Dim_Practice_Sites] s ON s.Tenant_ID = sa.Tenant_ID AND s.Site_ID = sa.Site_ID
        JOIN   [Audit].[Tenants] t ON t.Tenant_ID = sa.Tenant_ID
        WHERE  s.Site_Active = 1;

        ---------------------------------------------------------------- 2. which levels survive
        -- Ordinals: 0 the client, 1 Region, 2 Area, 3 Practice, 4 Site. The client is always a
        -- node (it is "everything"); the other four earn their place by offering a choice.
        DROP TABLE IF EXISTS #surv;
        SELECT DISTINCT Client_ID, 0 AS Ord INTO #surv FROM #h
        UNION ALL SELECT Client_ID, 1 FROM #h GROUP BY Client_ID HAVING COUNT(DISTINCT Region_Name)   > 1
        UNION ALL SELECT Client_ID, 2 FROM #h GROUP BY Client_ID HAVING COUNT(DISTINCT Area_Name)     > 1
        UNION ALL SELECT Client_ID, 3 FROM #h GROUP BY Client_ID HAVING COUNT(DISTINCT Practice_Key)  > 1
        UNION ALL SELECT Client_ID, 4 FROM #h GROUP BY Client_ID HAVING COUNT(DISTINCT Site_Key)      > 1;

        -- Depth is the position among the SURVIVORS, not the ordinal -- that is what makes the
        -- levels below a dropped one move up, and the indent match what the drop-down renders.
        DROP TABLE IF EXISTS #lvl;
        SELECT Client_ID, Ord,
               ROW_NUMBER() OVER (PARTITION BY Client_ID ORDER BY Ord) - 1 AS Depth,
               LAG(Ord) OVER (PARTITION BY Client_ID ORDER BY Ord)        AS Parent_Ord
        INTO   #lvl
        FROM   #surv;

        ---------------------------------------------------------------- 3. the nodes
        DROP TABLE IF EXISTS #node;
        SELECT DISTINCT
            h.Client_ID, l.Ord, l.Depth, l.Parent_Ord,
            CAST(CASE l.Ord WHEN 0 THEN CAST(h.Client_ID AS VARCHAR(64))
                            WHEN 1 THEN h.Region_Key   WHEN 2 THEN h.Area_Key
                            WHEN 3 THEN h.Practice_Key ELSE h.Site_Key END AS VARCHAR(64)) AS Node_Key,
            CAST(CASE l.Ord WHEN 0 THEN c.Client_Name
                            WHEN 1 THEN h.Region_Name   WHEN 2 THEN h.Area_Name
                            WHEN 3 THEN h.Practice_Name ELSE h.Site_Name END AS VARCHAR(200)) AS Node_Name,
            CAST(CASE l.Parent_Ord WHEN 0 THEN CAST(h.Client_ID AS VARCHAR(64))
                                   WHEN 1 THEN h.Region_Key   WHEN 2 THEN h.Area_Key
                                   WHEN 3 THEN h.Practice_Key ELSE NULL END AS VARCHAR(64)) AS Parent_Key
        INTO   #node
        FROM   #h h
        JOIN   #lvl l ON l.Client_ID = h.Client_ID
        JOIN   [Security].[Clients] c ON c.Client_ID = h.Client_ID;

        -- The drop-down string, and the parent's, so a roll knows where to send a value.
        DROP TABLE IF EXISTS #nd;
        SELECT n.Client_ID, n.Ord, n.Depth, n.Node_Key, n.Node_Name, n.Parent_Ord, n.Parent_Key,
               CAST(CASE WHEN n.Depth = 0 THEN n.Node_Name
                         ELSE REPLICATE(@FIG, n.Depth * 2) + @DSH + ' ' + n.Node_Name
                    END AS VARCHAR(200)) AS Selection
        INTO   #nd
        FROM   #node n;

        DROP TABLE IF EXISTS #edge;
        SELECT c.Client_ID, c.Selection AS Child_Selection, c.Depth AS Child_Depth,
               p.Selection AS Parent_Selection
        INTO   #edge
        FROM   #nd c
        JOIN   #nd p ON p.Client_ID = c.Client_ID AND p.Ord = c.Parent_Ord
                    AND p.Node_Key = c.Parent_Key
        WHERE  c.Parent_Ord IS NOT NULL;

        ---------------------------------------------------------------- 4. what was typed
        -- ==> AN ENTERED FIGURE LANDS ON THE DEEPEST SURVIVING LEVEL AT OR ABOVE THE ONE IT NAMES.
        -- <== Targets are entered per practice today, but a single-practice client HAS no practice
        -- node (the level offers no choice), so the figure belongs to that client's only node. The
        -- rule generalises: find the entered level's ordinal, take the deepest survivor not below
        -- it, and attach there. Without this, Maple's 525 entered targets would all drop silently.
        DROP TABLE IF EXISTS #ent;
        SELECT t.Client_ID, t.FY, t.Metric,
               CAST(CASE WHEN t.Target_Level = 'Practice' THEN 'All Roles'
                         ELSE t.Target_Level END AS VARCHAR(50)) AS Role,
               CAST(t.Target_Value AS DECIMAL(18,4)) AS Target_Value,
               CASE ISNULL(t.Level_Type,'Practice')
                    WHEN 'Group' THEN 0 WHEN 'Region' THEN 1 WHEN 'Area' THEN 2
                    WHEN 'Site'  THEN 4 ELSE 3 END AS Entered_Ord,
               ISNULL(t.Level_Key, CAST(t.Tenant_ID AS VARCHAR(64))) AS Entered_Key
        INTO   #ent
        FROM   [Input].[Targets] t
        WHERE  t.Target_Value IS NOT NULL AND t.Client_ID IS NOT NULL;

        -- the site rows the entered figure covers, then the node it attaches to
        DROP TABLE IF EXISTS #res;
        SELECT DISTINCT e.Client_ID, nd.Selection, e.Role, e.Metric, e.FY, e.Target_Value,
               CAST(1 AS BIT) AS Is_Entered
        INTO   #res
        FROM   #ent e
        JOIN   #h h ON h.Client_ID = e.Client_ID
                   AND e.Entered_Key = CASE e.Entered_Ord
                                             WHEN 0 THEN CAST(h.Client_ID AS VARCHAR(64))
                                             WHEN 1 THEN h.Region_Key WHEN 2 THEN h.Area_Key
                                             WHEN 4 THEN h.Site_Key   ELSE h.Practice_Key END
        -- the deepest surviving level at or above the one the figure names
        JOIN   #lvl l ON l.Client_ID = e.Client_ID AND l.Ord <= e.Entered_Ord
                     AND l.Depth = (SELECT MAX(l2.Depth) FROM #lvl l2
                                    WHERE l2.Client_ID = e.Client_ID AND l2.Ord <= e.Entered_Ord)
        JOIN   #nd nd ON nd.Client_ID = e.Client_ID AND nd.Ord = l.Ord
                     AND nd.Node_Key = CASE l.Ord
                                            WHEN 0 THEN CAST(h.Client_ID AS VARCHAR(64))
                                            WHEN 1 THEN h.Region_Key WHEN 2 THEN h.Area_Key
                                            WHEN 4 THEN h.Site_Key   ELSE h.Practice_Key END;

        ---------------------------------------------------------------- 5. quantities roll UP
        -- Child to parent, deepest first. A node already holding a value -- entered, or summed on
        -- an earlier pass -- is never overwritten, so an entered figure stops the roll and becomes
        -- the truth for everything above it. 'All Roles' only: a per-FTE role target does not sum.
        DECLARE @d INT = 4;
        WHILE @d >= 1
        BEGIN
            INSERT INTO #res (Client_ID, Selection, Role, Metric, FY, Target_Value, Is_Entered)
            SELECT e.Client_ID, e.Parent_Selection, r.Role, r.Metric, r.FY,
                   CAST(SUM(r.Target_Value) AS DECIMAL(18,4)), 0
            FROM   #res r
            JOIN   #edge e ON e.Client_ID = r.Client_ID AND e.Child_Selection = r.Selection
            JOIN   [Config].[Metric_Definitions] md ON md.Metric_Key = r.Metric AND md.Rolls_Up = 1
            WHERE  e.Child_Depth = @d
              AND  r.Role = 'All Roles'
              AND  NOT EXISTS (SELECT 1 FROM #res x
                               WHERE x.Client_ID = e.Client_ID AND x.Selection = e.Parent_Selection
                                 AND x.Role = r.Role AND x.Metric = r.Metric AND x.FY = r.FY)
            GROUP BY e.Client_ID, e.Parent_Selection, r.Role, r.Metric, r.FY;

            SET @d = @d - 1;
        END

        ---------------------------------------------------------------- 6. the rest rolls DOWN
        -- Parent to child, shallowest first: rates (a threshold cannot be derived upward from
        -- children) and every role figure (per-FTE, so it applies as-is wherever you stand).
        SET @d = 1;
        WHILE @d <= 4
        BEGIN
            INSERT INTO #res (Client_ID, Selection, Role, Metric, FY, Target_Value, Is_Entered)
            SELECT e.Client_ID, e.Child_Selection, r.Role, r.Metric, r.FY, r.Target_Value, 0
            FROM   #res r
            JOIN   #edge e ON e.Client_ID = r.Client_ID AND e.Parent_Selection = r.Selection
            LEFT   JOIN [Config].[Metric_Definitions] md ON md.Metric_Key = r.Metric
            WHERE  e.Child_Depth = @d
              AND  (r.Role <> 'All Roles' OR ISNULL(md.Rolls_Up, 0) = 0)
              AND  NOT EXISTS (SELECT 1 FROM #res x
                               WHERE x.Client_ID = e.Client_ID AND x.Selection = e.Child_Selection
                                 AND x.Role = r.Role AND x.Metric = r.Metric AND x.FY = r.FY);

            SET @d = @d + 1;
        END

        ---------------------------------------------------------------- 7. publish
        -- ==> THE RLS STAMP. <== A node above a practice has no natural tenant, so it takes
        -- MIN(Tenant_ID) of the practices beneath it. That is enough for the blanket rule to
        -- admit it for its own client and no other, which is the only boundary RLS has to carry
        -- here -- the app always pushes a [Selection], so narrowing BETWEEN nodes is a report
        -- concern. See the table header: this is an access key and nothing else.
        DROP TABLE IF EXISTS #stamp;
        SELECT b.Client_ID, b.[Selection], MIN(b.Tenant_ID) AS RLS_Tenant_ID
        INTO   #stamp
        FROM (
            SELECT DISTINCT nd.Client_ID, nd.[Selection], h.Tenant_ID
            FROM   #nd nd
            JOIN   #h h ON h.Client_ID = nd.Client_ID
                       AND nd.Node_Key = CASE nd.Ord
                                              WHEN 0 THEN CAST(h.Client_ID AS VARCHAR(64))
                                              WHEN 1 THEN h.Region_Key WHEN 2 THEN h.Area_Key
                                              WHEN 3 THEN h.Practice_Key ELSE h.Site_Key END
        ) b
        GROUP BY b.Client_ID, b.[Selection];

        DELETE FROM [Gold].[Fact_Node_Targets];
        SET @My_Deletes = @@ROWCOUNT;

        INSERT INTO [Gold].[Fact_Node_Targets]
            (pk_Node_Target, Client_ID, Tenant_ID, [Selection], [Role], Metric, Metric_Name, FY,
             Target_Value, Is_Entered, DW_Created_At)
        SELECT ROW_NUMBER() OVER (ORDER BY r.Client_ID, r.[Selection], r.Metric, r.[Role], r.FY),
               r.Client_ID, st.RLS_Tenant_ID, r.[Selection], r.[Role], r.Metric, md.Display_Name,
               r.FY, r.Target_Value, r.Is_Entered, SYSUTCDATETIME()
        FROM   #res r
        JOIN   #stamp st ON st.Client_ID = r.Client_ID AND st.[Selection] = r.[Selection]
        LEFT   JOIN [Config].[Metric_Definitions] md ON md.Metric_Key = r.Metric;
        SET @My_Inserts = @@ROWCOUNT;

        ---------------------------------------------------------------- 8. the bridge
        -- ==> WHAT EACH SELECTION COVERS, PUBLISHED ONCE. <== The period loader's NHS branch has
        -- to turn a contract's tenant into a selection, the report has to turn a selection into a
        -- set of sites, and /api/filters has to offer the list. All three need the same strings,
        -- and re-rendering them anywhere else risks a byte difference that a binary collation
        -- turns into a silent empty result. So the tree is resolved here, while it is in scope.
        DELETE FROM [Gold].[Dim_Hierarchy_Node];

        INSERT INTO [Gold].[Dim_Hierarchy_Node]
            (pk_Hierarchy_Node, Client_ID, [Selection], Depth, [Level], Node_Key,
             fk_Practice_Site, Tenant_ID, DW_Created_At)
        SELECT ROW_NUMBER() OVER (ORDER BY b.Client_ID, b.Depth, b.[Selection], b.pk_Practice_Site),
               b.Client_ID, b.[Selection], b.Depth, b.[Level], b.Node_Key,
               b.pk_Practice_Site, b.Tenant_ID, SYSUTCDATETIME()
        FROM (
            SELECT DISTINCT nd.Client_ID, nd.[Selection], nd.Depth, nd.Node_Key,
                   CAST(CASE nd.Ord WHEN 0 THEN 'Client' WHEN 1 THEN 'Region' WHEN 2 THEN 'Area'
                                    WHEN 3 THEN 'Practice' ELSE 'Site' END AS VARCHAR(10)) AS [Level],
                   h.pk_Practice_Site, h.Tenant_ID
            FROM   #nd nd
            JOIN   #h h ON h.Client_ID = nd.Client_ID
                       AND nd.Node_Key = CASE nd.Ord
                                              WHEN 0 THEN CAST(h.Client_ID AS VARCHAR(64))
                                              WHEN 1 THEN h.Region_Key WHEN 2 THEN h.Area_Key
                                              WHEN 3 THEN h.Practice_Key ELSE h.Site_Key END
        ) b;

        ---------------------------------------------------------------- 9. assert the stamp
        -- ==> THE STAMP IS ONLY SAFE IF IT CANNOT GO STALE. <== It is derived from client
        -- membership, so a practice moving client would make it wrong -- and a wrong RLS key
        -- fails OPEN, silently. The table is a full rebuild running after the AppDB sync, so this
        -- cannot happen; this proves it rather than trusting it. A failure here means the rebuild
        -- is no longer downstream of the membership it reads.
        DECLARE @bad INT, @err VARCHAR(400);
        SELECT @bad = COUNT(*)
        FROM   [Gold].[Fact_Node_Targets] nt
        WHERE  NOT EXISTS (SELECT 1 FROM [Input].[Client_Tenant] ct
                           WHERE ct.Client_ID = nt.Client_ID AND ct.Tenant_ID = nt.Tenant_ID);
        IF @bad <> 0
        BEGIN
            SET @err = 'Fact_Node_Targets: ' + CAST(@bad AS VARCHAR(12))
                     + ' row(s) stamped with a tenant that is not a member of their client. '
                     + 'The RLS stamp is stale -- do NOT publish the model.';
            THROW 51010, @err, 1;
        END

        DROP TABLE IF EXISTS #stamp;
        DROP TABLE IF EXISTS #h;    DROP TABLE IF EXISTS #surv; DROP TABLE IF EXISTS #lvl;
        DROP TABLE IF EXISTS #node; DROP TABLE IF EXISTS #nd;   DROP TABLE IF EXISTS #edge;
        DROP TABLE IF EXISTS #ent;  DROP TABLE IF EXISTS #res;

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
