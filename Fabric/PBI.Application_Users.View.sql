-- =============================================================================
-- PBI.[Application Users]
-- =============================================================================
-- Security view consumed by both the Power BI dataset (RLS filter on
-- 'Application Users') and the Flask application (_get_user_info).
-- Derives allowed Tenant IDs from the Client → Tenant mapping in
-- Security.Tenants, so tenant access is controlled in one place.
-- =============================================================================

CREATE OR ALTER VIEW [PBI].[Application Users] AS
SELECT  a.[User_UPN]  AS [User UPN],
        t.[Tenant_ID] AS [Tenant ID]
FROM    [Security].[Application_Users] a
JOIN    [Security].[Tenants]           t ON a.[Client_ID] = t.[Client_ID];
GO
