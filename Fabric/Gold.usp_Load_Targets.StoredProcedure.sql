--DECLARE @m VARCHAR(100)='PROD'; EXEC [Gold].[usp_Load_Targets] @Mode=@m;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Targets
--  Author           :  AIH
--  Initial Date     :  13/07/2026
--  History          :
--    *01     13/07/2026  AIH  Initial. Targets-only rebuild: runs the three target-fact
--                             loads in dependency order so a target change (after a new
--                             Input.Targets load from the template) can be applied WITHOUT
--                             a full Bronze->Gold build. Order matters --
--                             Fact_Effective_Targets reads Gold.Fact_Targets.
--                             NB: this rebuilds the FACTS only. Refresh the semantic model
--                             ('DM Dentally') afterwards so the report picks up the targets.
--  To Run           :  EXEC Gold.usp_Load_Targets @Mode='PROD';
--------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Targets]
GO
CREATE PROCEDURE [Gold].[usp_Load_Targets]
      @Mode VARCHAR(100) = 'TEST'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @i BIGINT, @u BIGINT, @d BIGINT;

    -- 1) Raw annual targets  (Input.Targets -> Gold.Fact_Targets)
    EXEC [Gold].[usp_Load_Fact_Targets]           @Mode = @Mode, @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;

    -- 2) Effective, hierarchy-resolved targets  (reads Gold.Fact_Targets -> AFTER step 1)
    EXEC [Gold].[usp_Load_Fact_Effective_Targets] @Mode = @Mode, @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;

    -- 3) Daily apportioned targets  (Input.Targets -> Gold.Fact_Daily_Targets; independent)
    EXEC [Gold].[usp_Load_Fact_Daily_Targets]     @Mode = @Mode, @Run_Inserts = @i OUT, @Run_Updates = @u OUT, @Run_Deletes = @d OUT;
END
GO
