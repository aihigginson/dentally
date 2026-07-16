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

-- BOOTSTRAP only: ensure the owner/admin logins exist so someone can always sign in and manage the
-- Team. Insert-if-missing (anti-join) -- must NOT clobber rows the Team screen manages. Staff rows
-- (Craig/Stephen/etc.) are now provisioned via /api/team, so they are no longer force-seeded here.
INSERT INTO Security.Application_Users
    (User_UPN, Client_ID, Display_Name, Maintain_Targets,
     Access_Home, Access_Revenue, Access_Patient, Access_Schedule, Access_Clinical, Access_NHS,
     Access_Day_Book, Access_Finance, Access_My_Data, Access_Marketing, Practitioner_Full_Name)
SELECT v.User_UPN, v.Client_ID, v.Display_Name, v.Maintain_Targets,
       v.Access_Home, v.Access_Revenue, v.Access_Patient, v.Access_Schedule, v.Access_Clinical, v.Access_NHS,
       v.Access_Day_Book, v.Access_Finance, v.Access_My_Data, v.Access_Marketing, v.Practitioner_Full_Name
FROM (VALUES
    ('aihigginson@outlook.com', 1,   'Andy Higginson Personal', 1, 1,1,1,1,1,1, 0,0,0,0, NULL),
    ('admin@analytically.info', 100, 'Andrew Higginson',        1, 1,1,1,1,1,1, 0,0,0,0, NULL)
) AS v(User_UPN, Client_ID, Display_Name, Maintain_Targets,
       Access_Home, Access_Revenue, Access_Patient, Access_Schedule, Access_Clinical, Access_NHS,
       Access_Day_Book, Access_Finance, Access_My_Data, Access_Marketing, Practitioner_Full_Name)
LEFT JOIN Security.Application_Users a ON LOWER(a.User_UPN) = LOWER(v.User_UPN)
WHERE a.User_UPN IS NULL;
GO
