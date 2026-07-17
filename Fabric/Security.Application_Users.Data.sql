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

-- BOOTSTRAP: ensure the owner/admin logins exist AND sit on the Full profile (all modules +
-- Maintain_Targets + Profile_Key='full'). The owner's row is self-locked in the Team screen, so it
-- is always Full -- and the practice IS billed for it. Staff rows (Craig/Stephen/etc.) are
-- provisioned via /api/team and are NOT force-seeded here.

-- 1) insert the owner rows if missing (fresh environments) --
INSERT INTO Security.Application_Users
    (User_UPN, Client_ID, Display_Name, Maintain_Targets,
     Access_Home, Access_Revenue, Access_Patient, Access_Schedule, Access_Clinical, Access_NHS,
     Access_Day_Book, Access_Finance, Access_My_Data, Access_Marketing, Practitioner_Full_Name, Profile_Key)
SELECT v.User_UPN, v.Client_ID, v.Display_Name, v.Maintain_Targets,
       v.Access_Home, v.Access_Revenue, v.Access_Patient, v.Access_Schedule, v.Access_Clinical, v.Access_NHS,
       v.Access_Day_Book, v.Access_Finance, v.Access_My_Data, v.Access_Marketing, v.Practitioner_Full_Name, v.Profile_Key
FROM (VALUES
    ('aihigginson@outlook.com', 1,   'Andy Higginson Personal', 1, 1,1,1,1,1,1, 1,1,1,1, NULL, 'full'),
    ('admin@analytically.info', 100, 'Andrew Higginson',        1, 1,1,1,1,1,1, 1,1,1,1, NULL, 'full')
) AS v(User_UPN, Client_ID, Display_Name, Maintain_Targets,
       Access_Home, Access_Revenue, Access_Patient, Access_Schedule, Access_Clinical, Access_NHS,
       Access_Day_Book, Access_Finance, Access_My_Data, Access_Marketing, Practitioner_Full_Name, Profile_Key)
LEFT JOIN Security.Application_Users a ON LOWER(a.User_UPN) = LOWER(v.User_UPN)
WHERE a.User_UPN IS NULL;
GO

-- 2) force existing owner rows onto the Full profile (self-locked = always Full) --
UPDATE Security.Application_Users
SET Maintain_Targets = 1,
    Access_Home = 1, Access_Revenue = 1, Access_Patient = 1, Access_Schedule = 1, Access_Clinical = 1,
    Access_NHS = 1, Access_Day_Book = 1, Access_Finance = 1, Access_My_Data = 1, Access_Marketing = 1,
    Profile_Key = 'full'
WHERE LOWER(User_UPN) IN ('aihigginson@outlook.com', 'admin@analytically.info');
GO
