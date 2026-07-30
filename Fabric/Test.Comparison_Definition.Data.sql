/****** Seed data: [Test].[Comparison_Definition] ******/
-- Cross-layer reconciliation rules. PASS when value(A) - value(B) = Expected.
-- Almost all expect 0 (full, consistent record sets Bronze -> Silver -> Gold).
-- The sentinel demo expects -1 (Gold dimension carries one extra -1 row).
-- Regression (Current vs Baseline per metric) is implicit and not listed here.
SET NOCOUNT ON
GO
TRUNCATE TABLE [Test].[Comparison_Definition]
GO
-- RETIRED 2026-07-29: the deterministic T11 regression suite is retired -- DEV now holds only
-- real tenant 100 (non-deterministic), so the metric/reconcile rows below were removed. The
-- TRUNCATE above leaves Test.Comparison_Definition empty; Run_Tests captures 0 rows and passes (RLS guards in
-- dw-tests still run). Re-seed here if a deterministic test tenant is reinstated.
