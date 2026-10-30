/****** Object:  View [Security].[vw_User_Tenant_Access]    Script Date: 27/09/2026 ******/
--------------------------------------------------------------------
--  View   :  Security.vw_User_Tenant_Access
--  Author :  AIH
--  Date   :  27/09/2026
--
--  ONE ROW PER (SIGNED-IN USER, TENANT THEY MAY SEE). The set Power BI's RLS filters on,
--  flattened to two columns so the semantic model imports ONE table and the rule is a single
--  expression -- rather than the model rebuilding the join and having to be revisited every
--  time the access model moves.
--
--  ==> IT MUST READ THE JUNCTION, NOT Audit.Tenants.Client_ID. <== The model previously
--  resolved a user's tenants through Audit.Tenants.Client_ID, which is a COLUMN on the tenant
--  and therefore one client per tenant. Under that rule the Analytically client -- which OWNS
--  no tenant and is granted access to every one of them (V186) -- resolves to the empty set,
--  and a support login pointed at it sees a blank report rather than every practice. That
--  failure mode is the reason this view exists: the join lives in one place, here.
--
--  Mirrors the app's own checks in _get_user_info, and deliberately so -- the app and the
--  reports must not be able to disagree about who may see what:
--      * inactive tenants excluded (ISNULL(Is_Active, 1) = 1)
--      * a row granting NOTHING is not an access-holder. An all-zero Application_Users row
--        left behind by a failed sync used to return a valid client, and prod carried 61 of
--        them while its sync was unknowingly running against dev. Excluded here too, so a
--        stale row cannot quietly widen a report's row set.
--
--  Columns are named [User UPN] and [Tenant ID] -- spaces, the presentation convention -- so
--  this is a DROP-IN for the table the model's RLS already filters, and the rule itself needs
--  only its table name changed. The existing expression is SELECTCOLUMNS(FILTER(...)), which
--  already returns a SET of tenant ids: it has always supported a user seeing many tenants.
--  Only its source was one-per-user, so nothing about the DAX has to become cleverer.
--
--  UPN is lower-cased. DAX string comparison is case-insensitive so the rule is unaffected
--  either way, but anything that later joins on this column is not.
--
--  ==> [Client ID] IS THE TENANT'S CLIENT, NOT THE USER'S. <== That is the whole trick, and
--  the other way round the column is useless: a support login sits on the vendor client, so
--  every row would carry that one id and narrowing to the client actually PICKED would match
--  nothing and blank the report. It is read from Input.Client_Tenant -- "which client does
--  this practice belong to" -- the same mapping the hierarchy screen maintains, so a practice
--  moved between clients moves here too, in one place.
--
--  ==> IT MAKES THE CLIENT PICKER WORK WITHOUT TOUCHING ANY OTHER RULE. <== Every
--  tenant-bearing table filters through SELECTCOLUMNS(FILTER('Application Users', ...)), and
--  row-level security COMPOSES: cut this view to the acting client and all fifty-odd rules
--  narrow with it. One comparison on a tiny lookup instead of a per-row test on every fact
--  table -- which is the other reason it belongs here and not in the rules.
--
--  A client that owns no practice -- the vendor client -- therefore resolves to no rows, and
--  its reports are empty. Correct and deliberate: "Analytically" is not a practice and has no
--  figures of its own. Support reads a real client by picking one.
--
--  JOIN, not LEFT JOIN, to Input.Client_Tenant. A tenant missing from that mapping would
--  otherwise carry a NULL client, match no selection, and vanish from every report while
--  still counting as permitted -- a gap that is total and findable beats one that is
--  intermittent and silent.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER VIEW [Security].[vw_User_Tenant_Access] AS
SELECT DISTINCT
       LOWER(au.User_UPN)                       AS [User UPN],
       cta.Tenant_ID                            AS [Tenant ID],
       ct.Client_ID                             AS [Client ID]
FROM   [Security].[Application_Users]      au
JOIN   [Security].[Client_Tenant_Access]   cta ON cta.Client_ID = au.Client_ID
JOIN   [Audit].[Tenants]                   t   ON t.Tenant_ID   = cta.Tenant_ID
JOIN   [Input].[Client_Tenant]             ct  ON ct.Tenant_ID  = cta.Tenant_ID
WHERE  ISNULL(t.Is_Active, 1) = 1
  AND  (  au.Maintain_Targets = 1
       OR ISNULL(au.Access_Home, 0)     = 1 OR ISNULL(au.Access_Revenue, 0)  = 1
       OR ISNULL(au.Access_Patient, 0)  = 1 OR ISNULL(au.Access_Schedule, 0) = 1
       OR ISNULL(au.Access_Clinical, 0) = 1 OR ISNULL(au.Access_NHS, 0)      = 1
       OR ISNULL(au.Access_Day_Book, 0) = 1 OR ISNULL(au.Access_Finance, 0)  = 1
       OR ISNULL(au.Access_My_Data, 0)  = 1 OR ISNULL(au.Access_Marketing, 0) = 1 )
GO
