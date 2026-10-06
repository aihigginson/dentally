/****** Object: Table [Gold].[Fact_Revenue_Cross_Charge] ******/
-- TWO rows per completed hygienist visit by a plan member: a debit against the dentist credited
-- with that member's capitation, and an equal credit to the hygienist who did the work.
-- Gold.vw_Fact_Revenue unions it back into the consolidated fact.
--
-- ==> THIS IS NOT ABOUT MOVING MONEY, IT IS ABOUT POUND-PER-HOUR. <== A plan patient's hygiene
-- visit costs them nothing and every penny of the fee was credited to the dentist, so the
-- hygienist's revenue-per-hour read about half what they actually earn and the dentist's read high.
-- Nothing settles here and no one is paid; the point is that both rates come out right.
--
-- ==> THE PAIR NETS TO ZERO, BY CONSTRUCTION. <== Equal and opposite, same patient, same date,
-- emitted from ONE source row via a CROSS APPLY of two signed legs, so a leg cannot be added,
-- filtered or reordered on its own. Practice-level capitation is unchanged; only its attribution
-- moves. The release guard asserts it rather than trusting the arithmetic.
--
-- ==> WHY BOTH PRACTITIONERS ARE ON BOTH LEGS. <== fk_Practitioner is THIS leg's practitioner, so
-- there is one active relationship to List Practitioners and a report filtered to a person finds
-- their own rows -- which is what My Data does, and why a measure keyed on Role returned blank on a
-- dentist's page. fk_Dentist and fk_Hygienist then name BOTH sides on BOTH rows, so the model can
-- alias List Practitioners twice and a workings report shows who paid and who received without
-- having to reach across to the other leg. Reaching across is not merely awkward: as a measure it
-- destroys auto-exist in a detail table and materialises the full date x patient x plan crossjoin.
--
-- (Built by Gold.usp_Load_Fact_Revenue, DROP/CREATE full rebuild. Revenue_Category is constant --
--  'Plan hygienist cross-charge' -- so the view supplies it as a literal.)
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Revenue_Cross_Charge]
GO
CREATE TABLE [Gold].[Fact_Revenue_Cross_Charge] (
      [pk_Revenue_Cross_Charge] BIGINT IDENTITY NOT NULL,
      [Tenant_ID]           INT               NOT NULL,
      [fk_Patient]          BIGINT            NOT NULL,
      [fk_Practitioner]     BIGINT            NOT NULL,   -- THIS leg: dentist on the debit, hygienist on the credit
      [fk_Dentist]          BIGINT            NOT NULL,   -- the dentist debited   (both legs)
      [fk_Hygienist]        BIGINT            NOT NULL,   -- the hygienist credited (both legs)
      [fk_Practice_Site]    BIGINT            NOT NULL,
      [fk_Payment_Plan]     BIGINT            NOT NULL,
      [fk_Date]             BIGINT            NOT NULL,   -- the visit date
      -- Signed: negative on the debit, positive on the credit. The sign is the information -- do
      -- not store it as ABS and recover the side from the leg, or the pair stops netting.
      [Amount]              DECIMAL(18,6)     NOT NULL,
      -- Says in words what the sign says in arithmetic, so the workings report is readable without
      -- the reader having to know the convention.
      [Leg]                 VARCHAR(10)       NOT NULL,   -- 'Debit' | 'Credit'
      -- Always 1. A share of a fee the warehouse has never observed being paid is still an
      -- estimate; see Gold.Fact_Revenue_Capitation.
      [Is_Estimated_Plan]   BIT               NOT NULL,
      [DW_Created_At]       DATETIME2(3)      NOT NULL
)
GO
