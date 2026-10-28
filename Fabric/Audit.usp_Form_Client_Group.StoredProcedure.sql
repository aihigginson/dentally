/****** Object:  StoredProcedure [Audit].[usp_Form_Client_Group]    Script Date: 28/10/2026 ******/
--------------------------------------------------------------------
--  Procedure : Audit.usp_Form_Client_Group
--  Author    : AIH
--  Date      : 28/10/2026
--
--  AMALGAMATE ALREADY-PROVISIONED TENANTS INTO ONE GROUP.
--
--  ==> PROVISIONING STAYS ONE TENANT, ONE CLIENT. <== Audit.usp_Provision_Tenant allocates
--  Tenant_ID == Client_ID on purpose, so a practice is landed and checked on its own before
--  it is anything else. Grouping is a SEPARATE, deliberate act -- this one -- run once the
--  members' data is known good. Nothing here provisions, ingests or builds.
--
--  ==> OWNERSHIP AND ACCESS ARE DIFFERENT THINGS, AND THE GROUP IS AN ACCESS FACT. <==
--    Audit.Tenants.Client_ID            = who the tenant was provisioned under. LEFT ALONE.
--    Security.Client_Tenant_Access      = which client may SEE which tenant. THIS is the group.
--  The app resolves identity through the ACCESS table, not ownership -- a client is valid to
--  act as if it has at least one active tenant GRANTED to it, which is not the same as owning
--  one (the vendor client owns nothing and sees everything). So forming a group means granting,
--  not repointing, and a member keeps its own billing and its own provisioning history.
--
--  That distinction is not academic: on DEV, tenant 12 is OWNED by client 11 and was never
--  GRANTED to it, so the one pair meant to behave as a group could not see its second member.
--  Running this fixes that case as well as creating new ones.
--
--  The hierarchy rows (region, area, site->area) are written here too, because a group with no
--  region is a group that cannot roll anything up. Members with no area given land in a single
--  default area so the chain is never broken -- a missing link silently drops a site out of
--  every roll-up above it, which reads as lost revenue rather than as a mapping gap.
--
--  IDEMPOTENT. Re-running with the same members changes nothing; re-running with an extra
--  member adds it. It never removes a grant it did not make.
--
--  To Run:
--    EXEC Audit.usp_Form_Client_Group
--         @Group_Client_ID = 500, @Group_Name = 'Northern Dental Group',
--         @Member_Tenant_IDs = '201,202,203,204',
--         @Region_Name = 'North', @Area_Name = 'Manchester';
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [Audit].[usp_Form_Client_Group]
(
    @Group_Client_ID   INT,
    @Group_Name        VARCHAR(255),
    @Member_Tenant_IDs VARCHAR(4000),          -- comma separated, already provisioned
    @Region_Name       VARCHAR(100) = NULL,    -- NULL -> one region named after the group
    @Area_Name         VARCHAR(100) = NULL,    -- NULL -> one area per member, named after it
    @Actor             VARCHAR(256) = 'form-group'
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @now DATETIME2(3) = SYSUTCDATETIME();

    DROP TABLE IF EXISTS #members;
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS INT) AS Tenant_ID
    INTO   #members
    FROM   STRING_SPLIT(@Member_Tenant_IDs, ',')
    WHERE  TRY_CAST(LTRIM(RTRIM(value)) AS INT) IS NOT NULL;

    -- ==> REFUSE RATHER THAN HALF-FORM A GROUP. <== A member that does not exist, or is not
    -- active, would be granted and mapped into the hierarchy and then never appear in a single
    -- figure -- a group that silently reports less than it should, which is the hardest kind of
    -- wrong number to notice.
    DECLARE @bad VARCHAR(4000) =
        (SELECT STRING_AGG(CAST(m.Tenant_ID AS VARCHAR(10)), ',')
         FROM   #members m
         LEFT JOIN Audit.Tenants t ON t.Tenant_ID = m.Tenant_ID AND ISNULL(t.Is_Active,1) = 1
         WHERE  t.Tenant_ID IS NULL);
    IF @bad IS NOT NULL
    BEGIN
        DECLARE @e1 VARCHAR(4000) = 'usp_Form_Client_Group: tenant(s) ' + @bad
            + ' do not exist or are not active. Provision and verify each member first.';
        THROW 51200, @e1, 1;
    END

    IF NOT EXISTS (SELECT 1 FROM #members)
        THROW 51201, 'usp_Form_Client_Group: no member tenants given.', 1;

    ---------------------------------------------------------------- 1. the group client
    IF NOT EXISTS (SELECT 1 FROM Security.Clients WHERE Client_ID = @Group_Client_ID)
        INSERT INTO Security.Clients (Client_ID, Client_Name)
        VALUES (@Group_Client_ID, @Group_Name);

    IF NOT EXISTS (SELECT 1 FROM Input.Client WHERE Client_ID = @Group_Client_ID)
        INSERT INTO Input.Client (Client_ID, Client_Name, Updated_At, Updated_By)
        VALUES (@Group_Client_ID, @Group_Name, @now, @Actor);

    ---------------------------------------------------------------- 2. access = the group
    INSERT INTO Security.Client_Tenant_Access (Client_ID, Tenant_ID, Granted_At, Granted_By)
    SELECT @Group_Client_ID, m.Tenant_ID, @now, @Actor
    FROM   #members m
    WHERE  NOT EXISTS (SELECT 1 FROM Security.Client_Tenant_Access a
                       WHERE a.Client_ID = @Group_Client_ID AND a.Tenant_ID = m.Tenant_ID);

    INSERT INTO Input.Client_Tenant (Tenant_ID, Client_ID, Updated_At, Updated_By)
    SELECT m.Tenant_ID, @Group_Client_ID, @now, @Actor
    FROM   #members m
    WHERE  NOT EXISTS (SELECT 1 FROM Input.Client_Tenant c WHERE c.Tenant_ID = m.Tenant_ID);

    UPDATE c SET c.Client_ID = @Group_Client_ID, c.Updated_At = @now, c.Updated_By = @Actor
    FROM   Input.Client_Tenant c
    JOIN   #members m ON m.Tenant_ID = c.Tenant_ID
    WHERE  c.Client_ID <> @Group_Client_ID;

    ---------------------------------------------------------------- 3. region
    DECLARE @Region_ID INT;
    SET @Region_Name = ISNULL(@Region_Name, @Group_Name);

    SELECT TOP 1 @Region_ID = Region_ID FROM Input.Client_Region
    WHERE  Client_ID = @Group_Client_ID AND Region_Name = @Region_Name;

    IF @Region_ID IS NULL
    BEGIN
        SET @Region_ID = (SELECT ISNULL(MAX(Region_ID), 0) + 1 FROM Input.Client_Region);
        INSERT INTO Input.Client_Region
            (Region_ID, Client_ID, Region_Name, Sort_Order, Is_Active, Updated_At, Updated_By)
        VALUES (@Region_ID, @Group_Client_ID, @Region_Name, 1, 1, @now, @Actor);
    END

    ---------------------------------------------------------------- 4. areas, one per member
    -- Named after the member unless the caller named one area for all of them. An area per
    -- practice is the shape that makes a two-level roll-up visible on test data; a single
    -- shared area collapses area and region into the same number and proves nothing.
    DROP TABLE IF EXISTS #areas;
    CREATE TABLE #areas (Tenant_ID INT, Area_ID INT, Area_Name VARCHAR(100));

    INSERT INTO #areas (Tenant_ID, Area_Name)
    SELECT m.Tenant_ID,
           ISNULL(@Area_Name, CAST(t.Tenant_Name AS VARCHAR(100)))
    FROM   #members m JOIN Audit.Tenants t ON t.Tenant_ID = m.Tenant_ID;

    UPDATE a SET a.Area_ID = ex.Area_ID
    FROM   #areas a
    JOIN   Input.Client_Area ex ON ex.Region_ID = @Region_ID AND ex.Area_Name = a.Area_Name;

    DECLARE @next INT = (SELECT ISNULL(MAX(Area_ID), 0) FROM Input.Client_Area);
    UPDATE a SET a.Area_ID = @next + x.rn
    FROM   #areas a
    JOIN  (SELECT Area_Name, ROW_NUMBER() OVER (ORDER BY Area_Name) AS rn
           FROM  (SELECT DISTINCT Area_Name FROM #areas WHERE Area_ID IS NULL) d) x
          ON x.Area_Name = a.Area_Name
    WHERE  a.Area_ID IS NULL;

    INSERT INTO Input.Client_Area
        (Area_ID, Region_ID, Area_Name, Sort_Order, Is_Active, Updated_At, Updated_By)
    SELECT DISTINCT a.Area_ID, @Region_ID, a.Area_Name, 1, 1, @now, @Actor
    FROM   #areas a
    WHERE  NOT EXISTS (SELECT 1 FROM Input.Client_Area e WHERE e.Area_ID = a.Area_ID);

    ---------------------------------------------------------------- 5. every site into its area
    -- ==> A SITE WITH NO AREA DROPS OUT OF EVERY ROLL-UP ABOVE IT. <== It still reports at site
    -- and practice level, so the loss shows up only as a group total that is quietly short.
    -- Read from Gold.Dim_Practice_Sites, so this must run AFTER the members have been built.
    INSERT INTO Input.Site_Area (Tenant_ID, Site_ID, Area_ID, Updated_At, Updated_By)
    SELECT s.Tenant_ID, s.Site_ID, a.Area_ID, @now, @Actor
    FROM   Gold.Dim_Practice_Sites s
    JOIN   #areas a ON a.Tenant_ID = s.Tenant_ID
    WHERE  s.Tenant_ID > 0
      AND  NOT EXISTS (SELECT 1 FROM Input.Site_Area e
                       WHERE e.Tenant_ID = s.Tenant_ID AND e.Site_ID = s.Site_ID);

    UPDATE e SET e.Area_ID = a.Area_ID, e.Updated_At = @now, e.Updated_By = @Actor
    FROM   Input.Site_Area e
    JOIN   #areas a ON a.Tenant_ID = e.Tenant_ID
    WHERE  e.Area_ID <> a.Area_ID;

    ---------------------------------------------------------------- 6. prove it joined up
    DECLARE @unmapped INT =
        (SELECT COUNT(*) FROM Gold.Dim_Practice_Sites s
         JOIN   #members m ON m.Tenant_ID = s.Tenant_ID
         WHERE  s.Tenant_ID > 0
           AND  NOT EXISTS (SELECT 1 FROM Input.Site_Area e
                            WHERE e.Tenant_ID = s.Tenant_ID AND e.Site_ID = s.Site_ID));
    IF @unmapped > 0
    BEGIN
        DECLARE @e2 VARCHAR(4000) = 'usp_Form_Client_Group: ' + CAST(@unmapped AS VARCHAR(10))
            + ' site(s) have no area. They would vanish from every roll-up above the practice.';
        THROW 51202, @e2, 1;
    END

    SELECT m.Tenant_ID,
           CAST(t.Tenant_Name AS VARCHAR(30))  AS tenant,
           t.Client_ID                         AS still_owned_by,
           @Group_Client_ID                    AS grouped_under,
           CAST(a.Area_Name AS VARCHAR(30))    AS area,
           @Region_Name                        AS region,
           (SELECT COUNT(*) FROM Gold.Dim_Practice_Sites s
            WHERE s.Tenant_ID = m.Tenant_ID AND s.Tenant_ID > 0) AS sites
    FROM   #members m
    JOIN   Audit.Tenants t ON t.Tenant_ID = m.Tenant_ID
    JOIN   #areas a        ON a.Tenant_ID = m.Tenant_ID
    ORDER BY m.Tenant_ID;
END
GO
