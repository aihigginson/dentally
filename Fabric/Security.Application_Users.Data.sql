-- =============================================================================
-- Security.Application_Users — seed data
-- =============================================================================
-- One row per user authorised to access Analytically.
-- User_UPN               : Azure AD user principal name (email address)
-- Client_ID              : FK to Security.Clients — the company this user belongs to
-- Display_Name           : Friendly name shown in the application header
-- Maintain_Targets       : 1 = user can see and edit the Targets screen
-- Access_*               : 1 = the matching menu/report is shown to this user (per-module
--                          subscription). Existing menus ON; the four not-yet-built
--                          modules (Day Book / Finance / My Data / Marketing) OFF.
-- Practitioner_Full_Name : scopes a future "My Data" view to one practitioner (else NULL)
-- =============================================================================

DELETE FROM Security.Application_Users;
GO

INSERT INTO Security.Application_Users
    (User_UPN, Client_ID, Display_Name, Maintain_Targets,
     Access_Home, Access_Revenue, Access_Patient, Access_Schedule, Access_Clinical, Access_NHS,
     Access_Day_Book, Access_Finance, Access_My_Data, Access_Marketing, Practitioner_Full_Name)
VALUES
    ('aihigginson@outlook.com',           1,   'Andy Higginson Personal', 1,  1, 1, 1, 1, 1, 1,  0, 0, 0, 0,  NULL),
    ('admin@analytically.info',           100, 'Andrew Higginson',        1,  1, 1, 1, 1, 1, 1,  0, 0, 0, 0,  NULL),
    ('craigjack@mapledental.co.uk',       100, 'Craig Jack',              0,  1, 1, 1, 1, 1, 1,  0, 0, 0, 0,  NULL),
    ('StephenRoberts@mapledental.co.uk',  100, 'Stephen Roberts',         0,  1, 1, 1, 1, 1, 1,  0, 0, 0, 0,  NULL);
GO
