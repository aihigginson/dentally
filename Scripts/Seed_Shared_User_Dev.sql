/* ============================================================================
   DEV ONLY -- give Skeleton Group a person who works at more than one practice.

   ==> THE SUBSCRIPTIONS SCREEN HAD NOTHING TO REGRESS AGAINST. <== It now shows one row per
   person keyed on EMAIL, because Dentally issues a user account per PRACTICE and a group's shared
   staff were appearing once per practice -- several rows offering to sell one person several
   seats. Neither environment could demonstrate that:

       client 11   24 roster rows, 24 distinct emails -- the generator gives each practice its
                   own staff, so nobody is shared
       client 20   12 rows, 12 distinct emails. Its four "Admin User" accounts LOOK duplicated but
                   are admin@t21.test .. admin@t24.test -- four genuine logins, four seats, and
                   correctly NOT merged
       client 100  one practice, so the shape cannot occur

   So the merge shipped verified by construction and simulation only. This fixture makes it real.

   ==> ONE PERSON, ONE EMAIL, FOUR PRACTICES. <== A group operations manager with an account at
   every practice, which is exactly the shape that produced the duplicate rows. Deliberately given
   a DIFFERENT Dentally user ID at each practice (900 + tenant), because that is how Dentally
   issues them -- the same ID everywhere would let a bug that keys on the ID pass by accident.

   Also deliberately: no practitioner record and no site at tenant 21, a role at the others, so the
   merge's first-non-empty rule is exercised rather than just its row count.

   After running: Silver.usp_Load_Users, then Gold.usp_Load_Dim_Users.
   ============================================================================ */
SET NOCOUNT ON;

/* Hand-inserted, like the rest of the skeleton. Tenants 21-24 are a test client and are not
   provisioned by Audit.usp_Provision_Tenant; every test tenant is < 100 by convention, which is
   also the guard below. */
IF EXISTS (SELECT 1 FROM Bronze.Users WHERE Tenant_ID >= 100 AND Email = 'ops@skeleton.test')
    THROW 51600, 'Seed_Shared_User_Dev touches test tenants only.', 1;
GO

DELETE FROM Bronze.Users WHERE Email = 'ops@skeleton.test';
GO

INSERT INTO Bronze.Users
    (ID, Created_At, Email, First_Name, Last_Name, Mobile_Phone, Permission_Level,
     Role, Site_ID, Title, Updated_At, Tenant_ID, DW_Loaded_At)
SELECT CAST(900 + v.Tenant_ID AS VARCHAR(20)),
       '2022-07-01T00:00:00.000+00:00',
       'ops@skeleton.test', 'Olivia', 'Price', '07000000111', 4,
       v.Role, v.Site_ID, 'Ms',
       '2022-07-01T00:00:00.000+00:00', v.Tenant_ID, SYSUTCDATETIME()
FROM  (VALUES
          (21, NULL,            NULL),      -- no role, no site: the merge must take these from below
          (22, 'Practice Manager', 't22-a'),
          (23, 'Practice Manager', 't23-a'),
          (24, 'Practice Manager', 't24-a')
      ) v (Tenant_ID, Role, Site_ID);

PRINT 'seeded the shared user at ' + CAST(@@ROWCOUNT AS VARCHAR(5)) + ' practice(s)';
GO

SELECT 'Bronze' AS layer, Tenant_ID, ID, Email, ISNULL(Role,'(null)') AS Role
FROM   Bronze.Users WHERE Email = 'ops@skeleton.test' ORDER BY Tenant_ID;
GO
