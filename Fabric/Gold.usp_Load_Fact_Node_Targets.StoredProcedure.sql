--------------------------------------------------------------------
--  Procedure : Gold.usp_Load_Fact_Node_Targets
--  Author    : AIH
--  History   :
--    *01  29/10/2026  AIH  Explode the sparse grid across every node of the hierarchy.
--    *02  29/10/2026  AIH  Keyed on the DROP-DOWN TEXT. Level_Type/Level_Key/Tenant_ID gone.
--    *03  30/10/2026  AIH  Read 'Client', the level the bridge publishes, not 'Group'.
--    *04  30/10/2026  AIH  A figure entered above every survivor lands on the shallowest.
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

        ---------------------------------------------------------------- 2. the fold
        -- ==> A NODE FOLDS INTO ITS PARENT WHEN IT IS AN ONLY CHILD. <== A child's sites are a
        -- subset of its parent's, so equal site COUNTS mean identical site sets, and an only
        -- child is exactly a child whose count matches its parent. Counts are non-increasing down
        -- a branch, so equal counts form a contiguous run and the entire decision is arithmetic.
        --
        -- Within a run, keep by rank -- Practice 0, Area 1, Region 2, Group 3, Site 4. That is
        -- the owner's "Practice outwards": Practice beats Site, Practice beats Area, Area beats
        -- Region, Region beats Group, and Practice beats Group by the same principle.
        --
        -- PER BRANCH, NOT PER LEVEL. One branch can keep Region and Practice while its sibling
        -- keeps only Practice. The rule this replaces asked "does this LEVEL offer a choice
        -- anywhere in the client", which left furniture on every branch that offered none.
        DROP TABLE IF EXISTS #hc;
        SELECT h.*,
               COUNT(*) OVER (PARTITION BY h.Client_ID)                  AS c_client,
               COUNT(*) OVER (PARTITION BY h.Client_ID, h.Region_Key)    AS c_region,
               COUNT(*) OVER (PARTITION BY h.Client_ID, h.Area_Key)      AS c_area,
               COUNT(*) OVER (PARTITION BY h.Client_ID, h.Practice_Key)  AS c_practice,
               c.Client_Name
        INTO   #hc
        FROM   #h h
        JOIN   [Security].[Clients] c ON c.Client_ID = h.Client_ID;

        -- every candidate node, once per branch it appears on, with its site count and its rank
        DROP TABLE IF EXISTS #cand;
        SELECT h.Client_ID, h.pk_Practice_Site, h.Tenant_ID,
               v.Ord, CAST(v.Node_Key AS VARCHAR(64)) AS Node_Key,
               CAST(v.Node_Name AS VARCHAR(200)) AS Node_Name,
               v.Site_Count,
               CASE v.Ord WHEN 3 THEN 0 WHEN 2 THEN 1 WHEN 1 THEN 2 WHEN 0 THEN 3 ELSE 4 END AS Keep_Rank
        INTO   #cand
        FROM   #hc h
        CROSS  APPLY (VALUES
                   (0, CAST(h.Client_ID AS VARCHAR(64)), h.Client_Name,   h.c_client),
                   (1, h.Region_Key,                     h.Region_Name,   h.c_region),
                   (2, h.Area_Key,                       h.Area_Name,     h.c_area),
                   (3, h.Practice_Key,                   h.Practice_Name, h.c_practice),
                   (4, h.Site_Key,                       h.Site_Name,     1)
               ) v (Ord, Node_Key, Node_Name, Site_Count);

        -- a level survives its run if nothing in the run outranks it
        DROP TABLE IF EXISTS #keep;
        SELECT c.*,
               MIN(c.Keep_Rank) OVER (PARTITION BY c.Client_ID, c.pk_Practice_Site, c.Site_Count)
                   AS Best_Rank
        INTO   #keep
        FROM   #cand c;

        ---------------------------------------------------------------- 3. the surviving nodes
        -- Survival is a property of the NODE, not of the branch it was examined on: its own count
        -- and its ancestors' are fixed, and a descendant can only share its count when it is an
        -- only child, which is also fixed. So DISTINCT here cannot disagree with itself.
        DROP TABLE IF EXISTS #nd;
        SELECT DISTINCT
               k.Client_ID, k.Ord, k.Node_Key, k.Node_Name,
               -- ==> THE STORED INDENT IS THE LEVEL, NOT THE DISPLAY POSITION. <== So a fold on
               -- one branch can never re-key a surviving node on another.
               CAST(CASE WHEN k.Ord = 0 THEN k.Node_Name
                         ELSE REPLICATE(@FIG, k.Ord * 2) + @DSH + ' ' + k.Node_Name
                    END AS VARCHAR(200)) AS [Selection]
        INTO   #nd
        FROM   #keep k
        WHERE  k.Keep_Rank = k.Best_Rank;

        -- Display depth: how many surviving ancestors a node has, which is what the drop-down
        -- should indent by. Counted on the branch, then DISTINCT -- a node's ancestor chain is
        -- unique, so every branch agrees.
        DROP TABLE IF EXISTS #disp;
        SELECT DISTINCT k.Client_ID, k.Ord, k.Node_Key,
               (SELECT COUNT(*) FROM #keep a
                 WHERE a.Client_ID = k.Client_ID AND a.pk_Practice_Site = k.pk_Practice_Site
                   AND a.Ord < k.Ord AND a.Keep_Rank = a.Best_Rank) AS Display_Depth
        INTO   #disp
        FROM   #keep k
        WHERE  k.Keep_Rank = k.Best_Rank;

        -- Parent = the nearest surviving ancestor, which is what the roll-up and roll-down walk.
        DROP TABLE IF EXISTS #edge;
        SELECT DISTINCT
               k.Client_ID,
               cn.[Selection] AS Child_Selection,
               d.Display_Depth AS Child_Depth,
               pn.[Selection] AS Parent_Selection
        INTO   #edge
        FROM   #keep k
        JOIN   #nd cn ON cn.Client_ID = k.Client_ID AND cn.Ord = k.Ord AND cn.Node_Key = k.Node_Key
        JOIN   #disp d ON d.Client_ID = k.Client_ID AND d.Ord = k.Ord AND d.Node_Key = k.Node_Key
        CROSS  APPLY (SELECT TOP 1 p.Ord, p.Node_Key
                      FROM   #keep p
                      WHERE  p.Client_ID = k.Client_ID AND p.pk_Practice_Site = k.pk_Practice_Site
                        AND  p.Ord < k.Ord AND p.Keep_Rank = p.Best_Rank
                      ORDER BY p.Ord DESC) par
        JOIN   #nd pn ON pn.Client_ID = k.Client_ID AND pn.Ord = par.Ord AND pn.Node_Key = par.Node_Key
        WHERE  k.Keep_Rank = k.Best_Rank;

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
               -- ==> THE LEVEL VOCABULARY IS THE ONE Dim_Hierarchy_Node PUBLISHES. <== That
               -- is 'Client', and it is what the screen sends back, because the screen's tabs ARE
               -- those published levels. This read 'Group' -- a name nothing has written since
               -- the bridge was published -- so a figure set on the "Whole client" tab fell to
               -- the ELSE (Practice), looked for a practice keyed '20', found none, and vanished
               -- with no row and no error. 'Group' stays recognised: it costs nothing.
               CASE ISNULL(t.Level_Type,'Practice')
                    WHEN 'Client' THEN 0 WHEN 'Group'  THEN 0
                    WHEN 'Region' THEN 1 WHEN 'Area'   THEN 2
                    WHEN 'Site'   THEN 4 ELSE 3 END AS Entered_Ord,
               ISNULL(t.Level_Key, CAST(t.Tenant_ID AS VARCHAR(64))) AS Entered_Key
        INTO   #ent
        FROM   [Input].[Targets] t
        WHERE  t.Target_Value IS NOT NULL AND t.Client_ID IS NOT NULL;

        -- ==> AN UNRECOGNISED LEVEL MUST NOT BECOME 'PRACTICE'. <== NULL legitimately means
        -- Practice, because the original roles grid writes no level at all. But a SPELLING the
        -- CASE above does not know became a practice key that matches nothing, and the rows then
        -- disappeared without a trace. Name it rather than lose it.
        DECLARE @unk VARCHAR(400);
        SELECT TOP 1 @unk = t.Level_Type
        FROM   [Input].[Targets] t
        WHERE  t.Level_Type IS NOT NULL
          AND  t.Level_Type NOT IN ('Client','Group','Region','Area','Practice','Site');
        IF @unk IS NOT NULL
        BEGIN
            SET @unk = 'Input.Targets.Level_Type = ''' + @unk + ''' is not a level this loader '
                     + 'knows (Client / Region / Area / Practice / Site). Those targets would '
                     + 'attach to the wrong node, or to none at all.';
            THROW 51011, @unk, 1;
        END

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
        -- ==> THE DEEPEST SURVIVING LEVEL AT OR ABOVE THE ONE THE FIGURE NAMES, ON THIS BRANCH.
        -- <== Folding is per branch now, so this cannot be asked of the client as a whole: a
        -- target entered at Practice attaches to the practice on a branch that kept it, and to
        -- whatever survives above it on a branch that folded it away. Asking per client would
        -- send both to the same node and silently merge two practices' targets.
        -- ==> AND IF THERE IS NOTHING AT OR ABOVE IT, THE SHALLOWEST SURVIVOR. <== Maple folds
        -- to a single PRACTICE node -- Practice outranks Group in the keep order -- so it has no
        -- Client node at all. A figure entered at Client is ordinal 0, its only survivor is
        -- ordinal 3, and with a bare `Ord <= Entered_Ord` the CROSS APPLY matched nothing and the
        -- target was dropped silently. Harmless while everything is entered at Practice; fatal the
        -- moment role targets move to client level, and fatal for the live customer first.
        --
        -- Ordering by "is it at or above" FIRST and then by depth gives both answers from one
        -- read: an at-or-above survivor still wins, and when there is none the shallowest survivor
        -- takes it -- which on that branch IS the whole client.
        CROSS  APPLY (SELECT TOP 1 kp.Ord, kp.Node_Key
                      FROM   #keep kp
                      WHERE  kp.Client_ID        = e.Client_ID
                        AND  kp.pk_Practice_Site = h.pk_Practice_Site
                        AND  kp.Keep_Rank        = kp.Best_Rank
                      ORDER BY CASE WHEN kp.Ord <= e.Entered_Ord THEN 0 ELSE 1 END,
                               CASE WHEN kp.Ord <= e.Entered_Ord THEN kp.Ord END DESC,
                               kp.Ord ASC) tgt
        JOIN   #nd nd ON nd.Client_ID = e.Client_ID AND nd.Ord = tgt.Ord
                     AND nd.Node_Key = tgt.Node_Key;

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
            (pk_Hierarchy_Node, Client_ID, [Selection], Display_Selection, Depth, [Level],
             Node_Key, fk_Practice_Site, Tenant_ID, DW_Created_At)
        SELECT ROW_NUMBER() OVER (ORDER BY b.Client_ID, b.Depth, b.[Selection], b.pk_Practice_Site),
               b.Client_ID, b.[Selection], b.Display_Selection, b.Depth, b.[Level],
               b.Node_Key, b.pk_Practice_Site, b.Tenant_ID, SYSUTCDATETIME()
        FROM (
            -- ==> TWO STRINGS, AND ONLY ONE OF THEM IS A KEY. <== [Selection] is indented by the
            -- node's LEVEL and never moves, so a target keyed on it survives a fold elsewhere in
            -- the client. [Display_Selection] is indented by position in the FOLDED tree, which
            -- is what reads correctly in a drop-down but would be a terrible thing to store a
            -- number against. The app renders the second and filters on the first.
            SELECT DISTINCT nd.Client_ID, nd.[Selection], nd.Node_Key, d.Display_Depth AS Depth,
                   CAST(CASE WHEN d.Display_Depth = 0 THEN nd.Node_Name
                             ELSE REPLICATE(@FIG, d.Display_Depth * 2) + @DSH + ' ' + nd.Node_Name
                        END AS VARCHAR(200)) AS Display_Selection,
                   CAST(CASE nd.Ord WHEN 0 THEN 'Client' WHEN 1 THEN 'Region' WHEN 2 THEN 'Area'
                                    WHEN 3 THEN 'Practice' ELSE 'Site' END AS VARCHAR(10)) AS [Level],
                   h.pk_Practice_Site, h.Tenant_ID
            FROM   #nd nd
            JOIN   #disp d ON d.Client_ID = nd.Client_ID AND d.Ord = nd.Ord AND d.Node_Key = nd.Node_Key
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
        DROP TABLE IF EXISTS #h;    DROP TABLE IF EXISTS #hc;   DROP TABLE IF EXISTS #cand;
        DROP TABLE IF EXISTS #keep; DROP TABLE IF EXISTS #nd;   DROP TABLE IF EXISTS #disp;
        DROP TABLE IF EXISTS #edge;
        DROP TABLE IF EXISTS #ent;  DROP TABLE IF EXISTS #res;

        SET @Run_Inserts = @My_Inserts; SET @Run_Updates = @My_Updates; SET @Run_Deletes = @My_Deletes;

        -- ==> THE COUNTS GO BACK THROUGH THE OUT PARAMETERS, AND NOTHING ELSE. <== This
        -- used to call Audit.ETL_Log_Record_Counts, which exists nowhere, and a CATCH that EXEC'd
        -- Audit.ETL_Error_Handler -- a FUNCTION taking no parameters -- with two of them. So every
        -- run threw at this tail AFTER the data had landed, and the CATCH threw again on top of
        -- it: a clean run and a real failure both came back as "ETL_Error_Handler has no
        -- parameters". Audit.ETL_Run_Process logs the counts, exactly as it does for every other
        -- Gold loader, which is why they do none of this.
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END
GO
