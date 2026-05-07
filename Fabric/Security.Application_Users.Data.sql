-- =============================================================================
-- Security.Application_Users — seed data
-- =============================================================================
-- One row per user authorised to access Analytically.
-- User_UPN   : Azure AD user principal name (email address)
-- Client_ID  : FK to Security.Clients — the company this user belongs to
-- Display_Name: Friendly name shown in the application header
-- =============================================================================

DELETE FROM Security.Application_Users;
GO

INSERT INTO Security.Application_Users (User_UPN, Client_ID, Display_Name)
VALUES ('aihigginson@2rrjxy.onmicrosoft.com', 1, 'Andrew I Higginson'),
       ('aihigginson@outlook.com',            1, 'Andy Higginson Personal');
GO
