/****** Object:  Table [Gold].[Dim_Patient_Status]    Script Date: 22/10/2026 ******/
--------------------------------------------------------------------
--  Table  :  Gold.Dim_Patient_Status
--  Author :  AIH
--  Purpose:  The patient lifecycle, as a dimension. Gold.Dim_Patients carries only
--            fk_Patient_Status; the name, the ordering and the Is_* flags live here, so a
--            measure asks Is_Lost = 1 instead of restating a CASE over Lapsed_Type,
--            Dentist_Recall_Date and a reminder age everywhere that needs it.
--
--            ==> NO Tenant_ID, AND THEREFORE NO RLS RULE. <== This is reference data: the
--            ladder is the same rungs for every practice. Every other new model table needs
--            a row-level rule adding by hand or it leaks across tenants -- this one must NOT
--            have one, because there is no tenant column to filter on. Deliberate, and
--            called out here rather than left to be rediscovered.
--
--            Keys are SEEDED AND FIXED, not IDENTITY. A status key is written into
--            Gold.Dim_Patients and bound by report filters and bookmarks, so it has to mean
--            the same thing after every rebuild.
--
--            ==> Is_Reportable EXISTS BECAUSE OF THE PRE-MIGRATION DEAD WEIGHT. <== A
--            practice that moved to Dentally brought its patient records but only part of
--            its appointment history: at the live tenant, patient records start in 1996 and
--            appointments start on 2012-02-29. Everyone who stopped attending before that
--            therefore looks identical to someone who never came -- 19,512 of them, against
--            4,050 who have no appointment even by Dentally own stats. Counting those as
--            lapsed patients overstates every retention figure in the product by an order of
--            magnitude, so they get their own rung with Is_Reportable = 0 and reports filter
--            on that one flag.
--
--            There is NO go-live date to key the archive off: creation dates run
--            continuously from 1996 to 2026. The rule is the absence of any relationship at
--            all -- no completed appointment, no invoice, no payment -- which is
--            self-identifying and needs no per-tenant configuration. Archiving them hides
--            no money: across thirty years those patients carry 1,274 pounds in total.
--
--            Archived is therefore tested BEFORE the lapsed rungs. A patient with no
--            attendance history was never lost, because they were never had.
--
--  History:
--    *01     22/10/2026  AIH V229: initial release.
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Dim_Patient_Status]
GO
CREATE TABLE [Gold].[Dim_Patient_Status](
	[pk_Patient_Status]    [int]           NOT NULL,
	[Status_Code]          [VARCHAR](40)   NOT NULL,
	[Status_Name]          [VARCHAR](60)   NOT NULL,
	[Status_Group]         [VARCHAR](20)   NOT NULL,   -- Active / At Risk / Lost / Never Attended / Archived / Unknown
	[Status_Description]   [VARCHAR](500)  NULL,
	[Sort_Order]           [int]           NOT NULL,   -- display order; NOT the derivation precedence
	[Is_Active]            [bit]           NOT NULL,
	[Is_At_Risk]           [bit]           NOT NULL,
	[Is_Lost]              [bit]           NOT NULL,
	[Is_Never_Attended]    [bit]           NOT NULL,
	[Is_Reportable]        [bit]           NOT NULL,   -- 0 = archive; keep out of every regular figure
	[Patient_Status_Count] [int]           NOT NULL,
	[DW_Created_At]        [datetime2](6)  NOT NULL,
	[DW_Updated_At]        [datetime2](6)  NOT NULL
)
GO
