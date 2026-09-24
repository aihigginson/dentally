/****** Object:  Table [Gold].[Dim_Affiliates]    Script Date: 24/09/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Dim_Affiliates
--  Notes  :  The referral partners we pay commission to. Sourced from Billing.Affiliate, which
--            the Admin screen maintains -- the same shape as the 13 Gold loads that read the
--            owner-curated Input schema.
--            Dim pattern: MERGE upsert, pk_Affiliate preserved across loads so the fact's
--            fk_Affiliate stays pointing at the same partner.
--            NOT TENANT-SCOPED. An affiliate is ours, not a practice's, and can have introduced
--            several practices -- so there is deliberately no Tenant_ID here.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Affiliates]
GO
CREATE TABLE [Gold].[Dim_Affiliates](
    [pk_Affiliate]        [bigint]        NOT NULL,
    [bk_Affiliate_ID]     [int]           NOT NULL,
    [Affiliate_Email]     [varchar](255)  NOT NULL,
    [Affiliate_Name]      [varchar](255)      NULL,
    [Standard_Commission_Pct] [decimal](6,3)  NULL,   -- fraction, 0.100 = 10%
    [Practices_Introduced]    [int]           NULL,
    [Created_Date]        [date]              NULL,
    [Notes]               [varchar](255)      NULL,
    [Affiliate_Count]     [int]               NULL,
    [DW_Created_At]       [datetime2](6)  NOT NULL,
    [DW_Updated_At]       [datetime2](6)  NOT NULL
)
GO
