-- =====================================================================
-- V127 -- Retire the interim vw_Dim_Practitioner_Day_Book view
-- =====================================================================
-- Superseded by Gold.vw_Dim_Site_Practitioner_Current (same base name as the
-- Aggregate_Site_Practitioner_Current it draws from). Drop the old Gold view so the
-- PBI view regen no longer generates PBI.[List Practitioner Day Book].
-- =====================================================================
DROP VIEW IF EXISTS Gold.vw_Dim_Practitioner_Day_Book;
GO
