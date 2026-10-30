/****** Object:  StoredProcedure [Audit].[usp_Form_Client_Group]    Script Date: 28/10/2026 ******/
--------------------------------------------------------------------
--  Procedure : Audit.usp_Form_Client_Group
--  Author    : AIH
--  Date      : 28/10/2026
--
--  GRANT A GROUP CLIENT ACCESS TO ALREADY-PROVISIONED TENANTS.
--
--  ==> PROVISIONING STAYS ONE TENANT, ONE CLIENT. <== Audit.usp_Provision_Tenant allocates
--  Tenant_ID == Client_ID on purpose, so a practice is landed and checked on its own before it
--  is anything else. Grouping is a SEPARATE, deliberate act -- this one -- run once the
--  members' data is known good. Nothing here provisions, ingests or builds.
--
--  ==> OWNERSHIP AND ACCESS ARE DIFFERENT THINGS, AND THIS PROC ONLY DOES ACCESS. <==
--    Audit.Tenants.Client_ID        = who the tenant was provisioned under. LEFT ALONE.
--    Security.Client_Tenant_Access  = which client may SEE which tenant. THIS is what it writes.
--  The app resolves identity through the ACCESS table, not ownership -- a client is valid to act
--  as if it has at least one active tenant GRANTED to it, which is not the same as owning one
--  (the vendor client owns nothing and sees everything). So forming a group means granting, not
--  repointing, and a member keeps its own billing and its own provisioning history.
--
--  ==> THE REGION/AREA HIERARCHY IS NOT WRITTEN HERE, AND MUST NOT BE. <==
--  Revision *02 removed it. Input.Client, Client_Tenant, Client_Region, Client_Area and
--  Site_Area are OWNED BY THE APPDB: Meta.usp_Sync_Input_From_AppDB DELETEs the warehouse copies
--  and rebuilds them from Input_Stage on every full sync. Anything this proc wrote into them
--  therefore survived only until that night -- a group that silently un-grouped itself. Worse,
--  Region_ID and Area_ID are IDENTITY columns in the AppDB, so the MAX(ID)+1 allocation used
--  here handed out values that database would later issue to something else.
--
--  Maintain the hierarchy where it lives:
--    * the admin screen in Web/app.py (the supported route), or
--    * SQL against AppDB-<env>.Input.*, then `python appdb_sync.py full` to push it down.
--  Then run this to grant the group its access, in either order -- the two halves are
--  independent, which is precisely the trap below.
--
--  ==> THE TWO HALVES BEING INDEPENDENT IS A REAL BUG SOURCE, NOT A TIDY SEPARATION. <==
--  Security.Client_Tenant_Access is in no sync set and is NOT derived from Input.Client_Tenant.
--  On DEV, tenant 12 was mapped to client 11 in the AppDB -- correct hierarchy, sites in areas,
--  everything looking right -- while client 11 had never been granted it, so the one pair meant
--  to behave as a group could not see its second member. Nothing reported an error. Running this
--  fixes that class of case as well as creating new ones.
--
--  ==> IT ALSO RETIRES THE MEMBER'S OWN CLIENT. <== Provisioning gives every tenant a client of
--  its own, which is right while it stands alone. Folded into a group it is a PRACTICE, and
--  leaving it in the client picker is both wrong and broken -- see step 3.
--
--  IDEMPOTENT. Re-running with the same members changes nothing; re-running with an extra member
--  adds it. The only grant it removes is the member's own, and only as part of folding it in.
--
--  To Run:
--    EXEC Audit.usp_Form_Client_Group
--         @Group_Client_ID = 20, @Group_Name = 'Skeleton Group',
--         @Member_Tenant_IDs = '21,22,23,24';
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

    IF NOT EXISTS (SELECT 1 FROM #members)
        THROW 51201, 'usp_Form_Client_Group: no member tenants given.', 1;

    -- ==> REFUSE RATHER THAN HALF-FORM A GROUP. <== A member that does not exist, or is not
    -- active, would be granted and then never appear in a single figure -- a group that silently
    -- reports less than it should, which is the hardest kind of wrong number to notice.
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

    ---------------------------------------------------------------- 1. the group client
    IF NOT EXISTS (SELECT 1 FROM Security.Clients WHERE Client_ID = @Group_Client_ID)
        INSERT INTO Security.Clients (Client_ID, Client_Name)
        VALUES (@Group_Client_ID, @Group_Name);

    ---------------------------------------------------------------- 2. access = the group
    INSERT INTO Security.Client_Tenant_Access (Client_ID, Tenant_ID, Granted_At, Granted_By)
    SELECT @Group_Client_ID, m.Tenant_ID, @now, @Actor
    FROM   #members m
    WHERE  NOT EXISTS (SELECT 1 FROM Security.Client_Tenant_Access a
                       WHERE a.Client_ID = @Group_Client_ID AND a.Tenant_ID = m.Tenant_ID);

    ---------------------------------------------------------------- 3. the member stops being a client
    -- ==> FOLDING A PRACTICE INTO A GROUP RETIRES ITS OWN CLIENT. <== Provisioning gives every
    -- tenant its own client, which is right while it stands alone. Once it is part of a group,
    -- "Skeleton Alpha" is a PRACTICE, not a client, and offering it in the client picker as well
    -- is both wrong and broken: the picker lists any client with a tenant granted to it, while
    -- Input.Client_Tenant now says that tenant belongs to the GROUP -- so selecting it filtered
    -- the reports to a client id that matches no row, and every tile read blank.
    --
    -- Revoking the self-grant is what retires it: Security.Client_Tenant_Access is what the
    -- picker is built from, and _get_user_info will not act as a client with no active tenant.
    -- The Security.Clients row STAYS -- Audit.Tenants.Client_ID still points at it, that is who
    -- the practice was provisioned under, and billing and invoicing read it. Ownership is not
    -- what is being withdrawn here; the ability to be SELECTED as a client is.
    --
    -- Only the member's own client, only for the tenant being folded in, and never the group
    -- itself or the vendor client -- which owns nothing, is granted everything, and is how
    -- support reaches any of this.
    DELETE a
    FROM   Security.Client_Tenant_Access a
    JOIN   #members m       ON m.Tenant_ID = a.Tenant_ID
    JOIN   Audit.Tenants t  ON t.Tenant_ID = m.Tenant_ID
    WHERE  a.Client_ID = t.Client_ID            -- the client it was provisioned under
      AND  a.Client_ID <> @Group_Client_ID      -- never the group we are forming
      AND  a.Client_ID <> 1;                    -- never the vendor client

    ---------------------------------------------------------------- 4. report, and warn loudly
    -- A member whose sites have no area still reports at site and practice level, so the loss
    -- shows up only as a group total that is quietly short. Input.Site_Area is read here, never
    -- written: if this column is not 0 the fix is in the AppDB, not in this proc.
    SELECT m.Tenant_ID,
           CAST(t.Tenant_Name AS VARCHAR(30)) AS tenant,
           t.Client_ID                        AS still_owned_by,
           @Group_Client_ID                   AS granted_to,
           (SELECT COUNT(*) FROM Gold.Dim_Practice_Sites s
            WHERE s.Tenant_ID = m.Tenant_ID AND s.Tenant_ID > 0) AS sites,
           (SELECT COUNT(*) FROM Gold.Dim_Practice_Sites s
            WHERE s.Tenant_ID = m.Tenant_ID AND s.Tenant_ID > 0
              AND NOT EXISTS (SELECT 1 FROM Input.Site_Area e
                              WHERE e.Tenant_ID = s.Tenant_ID AND e.Site_ID = s.Site_ID))
                                              AS sites_with_no_area
    FROM   #members m
    JOIN   Audit.Tenants t ON t.Tenant_ID = m.Tenant_ID
    ORDER BY m.Tenant_ID;
END
GO
