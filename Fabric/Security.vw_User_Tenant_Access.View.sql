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
--  UPN is lower-cased: USERPRINCIPALNAME() casing is not guaranteed to match what the sync
--  wrote, and a case-sensitive miss fails OPEN in a DAX "IN" test if the rule is written
--  carelessly -- so normalise on this side of the boundary.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER VIEW [Security].[vw_User_Tenant_Access] AS
SELECT DISTINCT
       LOWER(au.User_UPN)                       AS [User_UPN],
       cta.Tenant_ID                            AS [Tenant_ID]
FROM   [Security].[Application_Users]      au
JOIN   [Security].[Client_Tenant_Access]   cta ON cta.Client_ID = au.Client_ID
JOIN   [Audit].[Tenants]                   t   ON t.Tenant_ID   = cta.Tenant_ID
WHERE  ISNULL(t.Is_Active, 1) = 1
  AND  (  au.Maintain_Targets = 1
       OR ISNULL(au.Access_Home, 0)     = 1 OR ISNULL(au.Access_Revenue, 0)  = 1
       OR ISNULL(au.Access_Patient, 0)  = 1 OR ISNULL(au.Access_Schedule, 0) = 1
       OR ISNULL(au.Access_Clinical, 0) = 1 OR ISNULL(au.Access_NHS, 0)      = 1
       OR ISNULL(au.Access_Day_Book, 0) = 1 OR ISNULL(au.Access_Finance, 0)  = 1
       OR ISNULL(au.Access_My_Data, 0)  = 1 OR ISNULL(au.Access_Marketing, 0) = 1 )
GO
