/****** Object:  Table [Gold].[Dim_Plan_Payer]    Script Date: 22/10/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Dim_Plan_Payer
--  Author :  AIH
--  Purpose:  Who paid for a treatment plan. Gold.Fact_Treatment_Plans carries only
--            fk_Plan_Payer; the name and the Is_* flags live here.
--
--            ==> NO Tenant_ID, THEREFORE NO RLS RULE. <== The four payers exist for every
--            customer. Same reasoning as Gold.Dim_Patient_Status: there is no tenant column
--            to filter on, so a row-level rule here would be wrong rather than missing.
--
--            ==> THIS EXISTS BECAUSE "NO PRIVATE VALUE" MEANT FOUR DIFFERENT THINGS. <==
--            55% of the live practice's plans carry Private_Treatment_Value = 0, which reads
--            as "nothing happened" and is wrong: 99%+ of them have a completed item. They
--            are real clinical work someone else paid for. Of 39,340 such plans, 21,272 were
--            capitation members, 13,416 were NHS, and 4,541 had no payer at all.
--
--            Is_Clinical_Activity is 0 for No Payer alone, and that is a judgement worth
--            stating: that bucket mixes genuine ex-gratia treatment (fillings redone for
--            nothing) with plans whose only items are General Note, Notes, Prescription or
--            Covid Screening Questions -- filing, not dentistry. Counting those as activity
--            overstates what the practice did.
--
--  History:
--    *01     22/10/2026  AIH V231: initial release.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Plan_Payer]
GO
CREATE TABLE [Gold].[Dim_Plan_Payer](
	[pk_Plan_Payer]        [int]           NOT NULL,
	[Payer_Code]           [VARCHAR](20)   NOT NULL,
	[Payer_Name]           [VARCHAR](40)   NOT NULL,
	[Payer_Description]    [VARCHAR](500)  NULL,
	[Sort_Order]           [int]           NOT NULL,
	[Is_Charged]           [bit]           NOT NULL,   -- money changed hands for this plan
	[Is_Clinical_Activity] [bit]           NOT NULL,   -- 0 = do not count as work done
	[Plan_Payer_Count]     [int]           NOT NULL,
	[DW_Created_At]        [datetime2](6)  NOT NULL,
	[DW_Updated_At]        [datetime2](6)  NOT NULL
)
GO
