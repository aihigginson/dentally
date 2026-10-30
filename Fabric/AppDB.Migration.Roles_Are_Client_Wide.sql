/* ============================================================================
   APPDB MIGRATION -- a role target belongs to the CLIENT, not to one of its practices.

   ==> RUN THIS AGAINST AppDB-<env>. <== AppDB-dev first, prove it, then AppDB-prod.
   Requires AppDB.Migration.Target_Node_Key.sql to have run: this writes two rows that differ only
   by their node address, which the old four-column primary key could not hold.

   ==> WHY. <== A role target is per FTE -- the measures multiply it by the full-time equivalent of
   whoever is in view -- so it states what one person in that role should deliver. That does not
   change between a group's practices, and the loader never rolls a role figure UP, only down. It
   is therefore entered once for the client. The screen was writing it per practice, against
   whichever tenant happened to come back first, which for a group meant the figure applied to one
   practice and silently not the rest.

   ==> WHERE THEY GO. <== To the client's own node, read from the published hierarchy rather than
   assumed: Maple's tree folds to a single PRACTICE node -- Practice outranks Group in the keep
   order -- so its whole-client address is ('Practice','100'), not ('Client','100'). Writing an
   address the loader cannot resolve would drop the row silently. AppDB cannot see
   Gold.Dim_Hierarchy_Node, so the shape is derived here from Input.Client_Tenant: a client with one
   tenant has no Client node and keys on its practice; a client with several keeps its Client node.

   ==> WHICH VALUE WINS WHEN TWO PRACTICES DISAGREE. <== MIN(Tenant_ID)'s, the same rule
   Gold.usp_Load_Aggregate_Period_Targets already uses to choose a client's calendar tenant. On DEV
   that affects exactly one role -- client 11's Hygienist, on ten metrics across two financial years
   -- and keeps the hand-set figures rather than the ones calibrated from actuals. Every other role
   in every client exists on a single tenant, so for them the move is lossless.

   The practice-level 'Practice' rows -- the whole-practice figure, which publishes as 'All Roles'
   -- are NOT touched. They are a different thing: they roll up, they are per node, and the
   per-level tabs own them.

   Idempotent: re-running moves nothing, because there is nothing left at practice level to move.
   ============================================================================ */
SET NOCOUNT ON;

IF COL_LENGTH('Input.Targets', 'Node_Key') IS NULL
    THROW 51201, 'Run AppDB.Migration.Target_Node_Key.sql first -- the old primary key cannot hold two rows that differ only by node address.', 1;
GO

/* ---- 1. each client's whole-client address ------------------------------ */
/* One tenant  -> the hierarchy folds to that practice, so ('Practice', tenant).
   Several     -> the Client node survives, so ('Client', client).
   This mirrors what Gold.usp_Load_Fact_Node_Targets publishes; the loader's attach rule now also
   falls back to the shallowest surviving node, so a near-miss here degrades rather than vanishes. */
DROP TABLE IF EXISTS #addr;
SELECT ct.Client_ID,
       CAST(CASE WHEN COUNT(*) = 1 THEN 'Practice' ELSE 'Client' END AS VARCHAR(10)) AS Level_Type,
       CAST(CASE WHEN COUNT(*) = 1 THEN CAST(MIN(ct.Tenant_ID) AS VARCHAR(64))
                 ELSE CAST(ct.Client_ID AS VARCHAR(64)) END AS VARCHAR(64))          AS Level_Key,
       MIN(ct.Tenant_ID)                                                             AS Stamp_Tenant
INTO   #addr
FROM   Input.Client_Tenant ct
GROUP  BY ct.Client_ID;

/* ---- 2. one surviving figure per (client, role, metric, FY) ------------- */
/* MIN(Tenant_ID) decides, so the choice is deterministic and reviewable rather than whichever row
   a MERGE happened to see last. */
DROP TABLE IF EXISTS #win;
SELECT t.Client_ID, t.Target_Level, t.Metric, t.FY,
       MIN(t.Tenant_ID) AS Src_Tenant
INTO   #win
FROM   Input.Targets t
WHERE  t.Target_Level <> 'Practice'
  AND  ISNULL(t.Level_Type, 'Practice') = 'Practice'
  AND  t.Client_ID IS NOT NULL
GROUP  BY t.Client_ID, t.Target_Level, t.Metric, t.FY;

DROP TABLE IF EXISTS #move;
SELECT w.Client_ID, w.Target_Level, w.Metric, w.FY, t.Target_Value, t.Updated_By,
       a.Level_Type, a.Level_Key, a.Stamp_Tenant
INTO   #move
FROM   #win w
JOIN   Input.Targets t ON t.Client_ID    = w.Client_ID
                      AND t.Tenant_ID    = w.Src_Tenant
                      AND t.Target_Level = w.Target_Level
                      AND t.Metric       = w.Metric
                      AND t.FY           = w.FY
                      AND ISNULL(t.Level_Type, 'Practice') = 'Practice'
JOIN   #addr a ON a.Client_ID = w.Client_ID;

SELECT 'to move' AS step, COUNT(*) AS client_rows FROM #move;
GO

/* ---- 3. out with the practice-scoped role rows, in with the client's ---- */
/* Delete first: a client whose address resolves to ('Practice', tenant) would otherwise collide
   with the row it is replacing, because that is the same address. */
DELETE FROM Input.Targets
WHERE  Target_Level <> 'Practice'
  AND  ISNULL(Level_Type, 'Practice') = 'Practice'
  AND  Client_ID IS NOT NULL;
PRINT 'removed practice-scoped role rows: ' + CAST(@@ROWCOUNT AS VARCHAR(12));

INSERT INTO Input.Targets
    (Tenant_ID, Client_ID, FY, Metric, Target_Level, Target_Value,
     Level_Type, Level_Key, Updated_At, Updated_By)
SELECT m.Stamp_Tenant, m.Client_ID, m.FY, m.Metric, m.Target_Level, m.Target_Value,
       m.Level_Type, m.Level_Key, SYSUTCDATETIME(), m.Updated_By
FROM   #move m;
PRINT 'added client-wide role rows: ' + CAST(@@ROWCOUNT AS VARCHAR(12));
GO

/* ---- 4. prove it, rather than assume it --------------------------------- */
SELECT 'role rows by level' AS check_, Client_ID, Level_Type, Target_Level,
       COUNT(*) AS rows_, COUNT(DISTINCT Tenant_ID) AS tenants
FROM   Input.Targets WHERE Target_Level <> 'Practice'
GROUP  BY Client_ID, Level_Type, Target_Level
ORDER  BY Client_ID, Target_Level, Level_Type;

/* No role may still be held at a PRACTICE address in a client that has more than one practice --
   that is the shape this migration exists to remove. A client figure overridden at a region or a
   site is NOT that: it is the roll-down rule working, so it must not be reported here. */
SELECT 'still practice-scoped' AS check_, t.Client_ID, t.Target_Level, COUNT(*) AS rows_
FROM   Input.Targets t
JOIN   (SELECT Client_ID FROM Input.Client_Tenant
        GROUP BY Client_ID HAVING COUNT(*) > 1) g ON g.Client_ID = t.Client_ID
WHERE  t.Target_Level <> 'Practice'
  AND  ISNULL(t.Level_Type, 'Practice') = 'Practice'
GROUP  BY t.Client_ID, t.Target_Level;

/* The whole-practice rows are a different thing and must be untouched. */
SELECT 'All Roles rows untouched' AS check_, Client_ID, COUNT(*) AS rows_
FROM   Input.Targets WHERE Target_Level = 'Practice'
GROUP  BY Client_ID ORDER BY Client_ID;
GO

DROP TABLE IF EXISTS #addr;
DROP TABLE IF EXISTS #win;
DROP TABLE IF EXISTS #move;
GO
