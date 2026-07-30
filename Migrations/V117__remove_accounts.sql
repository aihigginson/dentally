-- =====================================================================
-- V117 -- Surgically remove the Dentally patient-Accounts concept (pre-go-live).
-- Drops Bronze/Silver/Dim Accounts, their load procs, and the generated PBI view.
-- The invoice facts' fk_Account column is dropped via the DROP/CREATE re-deploy of
-- those tables (in the same manifest). The Xero GL Account / Finance concept is a
-- SEPARATE thing (List GL Account, _Finance) and is deliberately left untouched.
-- =====================================================================
DROP VIEW IF EXISTS PBI.[List Accounts];
DROP VIEW IF EXISTS PBI.[Accounts];
GO
DROP TABLE IF EXISTS Gold.Dim_Accounts;
DROP TABLE IF EXISTS Silver.Accounts;
DROP TABLE IF EXISTS Bronze.Accounts;
GO
DROP PROCEDURE IF EXISTS Gold.usp_Load_Dim_Accounts;
DROP PROCEDURE IF EXISTS Silver.usp_Load_Accounts;
DROP PROCEDURE IF EXISTS Bronze.usp_Load_Accounts;
GO
