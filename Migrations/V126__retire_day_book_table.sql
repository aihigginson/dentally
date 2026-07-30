-- =====================================================================
-- V126 -- Retire the separate Aggregate_Practitioner_Day_Book table
-- =====================================================================
-- Its per-practitioner Day Book action counts are now folded into
-- Gold.Aggregate_Site_Practitioner_Current (split by site). Drop the old
-- table + its load SP if a prior V125 deploy created them.
-- =====================================================================
DROP TABLE     IF EXISTS Gold.Aggregate_Practitioner_Day_Book;
GO
DROP PROCEDURE IF EXISTS Gold.usp_Load_Aggregate_Practitioner_Day_Book;
GO
