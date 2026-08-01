-- V137: recreate Gold.Dim_Date_Grouping WITH Tenant_ID before the tenant-specific load SP deploys.
-- Fabric validates SP bodies eagerly at CREATE time, so the load SP's INSERT (Tenant_ID, ...) needs
-- the table to already carry Tenant_ID. The load SP DROP/CREATEs it again at runtime (idempotent).
DROP TABLE IF EXISTS Gold.Dim_Date_Grouping;
GO
CREATE TABLE Gold.Dim_Date_Grouping (
      Tenant_ID             INT         NOT NULL
    , Date_Grouping         VARCHAR(30) NOT NULL
    , fk_Date               INT         NOT NULL
    , fk_Date_Previous_Year INT         NOT NULL
);
GO
