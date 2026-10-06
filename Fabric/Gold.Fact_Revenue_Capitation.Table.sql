/****** Object: Table [Gold].[Fact_Revenue_Capitation] ******/
-- One row per member per WEEK-WITHIN-MONTH segment of a plan spell. The bulk of revenue by row
-- count (~600k of ~830k), which is most of why the shared table was expensive to query for
-- anything else. Gold.vw_Fact_Revenue unions it back into the consolidated fact.
--
-- ==> EVERY FIGURE IN THIS TABLE IS AN ESTIMATE. IT IS NOT MONEY WE HAVE SEEN. <== Dentally holds
-- no membership income: a plan patient's fee is collected by the PLAN PROVIDER and the
-- authoritative figures live in the spreadsheets they send the practice. This is RECONSTRUCTED
-- from clinical evidence -- a completed, non-charged Exam/Hygiene course implies membership that
-- month -- and priced from the owner-curated Input.Plan_Capitation_Rate. Good for trend, mix and
-- per-patient value; NOT the number to reconcile to the bank. The full reasoning, and the four
-- assumptions it rests on, are in the header of Gold.usp_Load_Fact_Revenue.
--
-- ==> A SEGMENT SPANS NEITHER A WEEK NOR A MONTH BOUNDARY. <== That is the whole point of the
-- grain: weekly AND monthly reports both sum exactly, at 4.4x fewer rows than the member-day grain
-- this replaced (2,613,357 -> 588,854). Amount is DECIMAL(18,6) so the sum over segments equals the
-- sum over days exactly rather than approximately.
--
-- fk_Practitioner is the DENTIST credited with the member -- Dim_Patients.Dentist_Practitioner_ID.
-- Gold.Fact_Revenue_Cross_Charge is what moves a share of this to the hygienist who did the work.
--
-- (Built by Gold.usp_Load_Fact_Revenue, DROP/CREATE full rebuild. Revenue_Category is constant
--  here -- 'Plan Capitation (estimated)' -- so the view supplies it as a literal rather than
--  storing the same 600k strings.)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Revenue_Capitation]
GO
CREATE TABLE [Gold].[Fact_Revenue_Capitation] (
      [pk_Revenue_Capitation] BIGINT IDENTITY NOT NULL,
      [Tenant_ID]           INT               NOT NULL,
      [fk_Patient]          BIGINT            NOT NULL,
      [fk_Practitioner]     BIGINT            NOT NULL,   -- the dentist credited with the member
      [fk_Practice_Site]    BIGINT            NOT NULL,
      [fk_Payment_Plan]     BIGINT            NOT NULL,
      [fk_Date]             BIGINT            NOT NULL,   -- the segment's first day
      [Amount]              DECIMAL(18,6)     NOT NULL,
      -- 1 = the plan was attributed by the Is_Default fallback because Dentally no longer records
      -- the patient's own plan (a lapsed member), so the RATE is the default plan's, not theirs.
      -- These rows are an estimate within an estimate and must stay distinguishable.
      [Is_Estimated_Plan]   BIT               NOT NULL,
      [DW_Created_At]       DATETIME2(3)      NOT NULL
)
GO
