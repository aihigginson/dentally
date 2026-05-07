-- =============================================================================
-- Security.User_Tenants — seed data
-- =============================================================================
-- One row per user-tenant combination — controls which Dentally accounts
-- each application user can see in the embedded reports and KPIs.
-- =============================================================================

DELETE FROM Security.User_Tenants;
GO

INSERT INTO Security.User_Tenants (User_UPN, Tenant_ID)
VALUES ('aihigginson@2rrjxy.onmicrosoft.com', 1),
       ('aihigginson@2rrjxy.onmicrosoft.com', 2),
       ('aihigginson@outlook.com',            1),
       ('aihigginson@outlook.com',            2);
GO
