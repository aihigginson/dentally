-- =============================================================================
-- Security.Application_Users — seed data
-- =============================================================================
-- One row per user authorised to access the embedded Power BI application.
-- User_UPN   : Azure AD user principal name (email address)
-- Tenant_ID  : Controls which tenant's data the user can see (RLS)
-- Display_Name: Friendly name shown in the application
-- =============================================================================

DELETE FROM Security.Application_Users;
GO

INSERT INTO Security.Application_Users (User_UPN, Tenant_ID, Display_Name)
VALUES ('aihigginson@2rrjxy.onmicrosoft.com', 1, 'Andrew I Higginson');
GO
