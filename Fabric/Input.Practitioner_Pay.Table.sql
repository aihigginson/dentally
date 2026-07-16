/****** Object:  Table [Input].[Practitioner_Pay]  ******/
-- Per-practitioner associate pay share (% of their production), captured in the app's
-- admin Settings screen. Feeds practitioner contribution (production - associate pay).
-- One row per (Tenant_ID, Practitioner_ID); upserted (DELETE+INSERT) by /api/practitioner-pay.
-- NOTE: this canonical DROP/CREATE is for reference / full rebuilds. Live deploys use the
-- idempotent Migrations/V039__practitioner_pay.sql so re-deploys never wipe entered data.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Input].[Practitioner_Pay]
GO
CREATE TABLE [Input].[Practitioner_Pay] (
    [pk_practitioner_pay] BIGINT        IDENTITY NOT NULL,
    [Tenant_ID]           INT           NOT NULL,
    [Practitioner_ID]     INT           NOT NULL,
    [Associate_Pct]       DECIMAL(6,3)  NULL,
    [FTE] [DECIMAL](4,2) NULL,
    [DW_Created_At]       DATETIME2(3)  NOT NULL,
    [DW_Updated_At]       DATETIME2(3)  NOT NULL
)
GO
