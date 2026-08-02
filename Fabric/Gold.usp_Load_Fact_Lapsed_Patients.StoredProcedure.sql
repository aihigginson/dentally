-- DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_Lapsed_Patients] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
----------------------------------------------------------------------------------------------------
--   Stored Procedure : Gold.usp_Load_Fact_Lapsed_Patients
--   Author           : AIH
--   Intitial Date    : 01/08/2026
--   History          :
--       *01          01/08/2026  AIH  Initial Release
--
--   Purpose          : Materialises one row per lapsed patient (Dim_Patients.Lapsed_Type IS NOT NULL),
--                      dated by the lapse date, so a patient-level lapsed report slices natively by
--                      Period / Site / Practitioner (and Payment Plan) -- the star-schema alternative
--                      to date-relating the patient dimension. Carries Lapsed_Type / Lapsed_Reason /
--                      Lapsed_Date for the deactivated-vs-long-silent breakdown. Full rebuild
--                      (DROP/CREATE). GOLD_AGG -- reads Gold.Dim_Patients (+ dims for surrogate keys).
--
--   Dependencies     : Gold Dim_Patients / Dim_Practitioners / Dim_Practice_Sites / Dim_Payment_Plans.
--
--   To Run           : DECLARE @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT;
--                      EXEC Gold.usp_Load_Fact_Lapsed_Patients
--                           @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
----------------------------------------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_Lapsed_Patients]    Script Date: 08/01/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_Lapsed_Patients]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_Lapsed_Patients]
(
        @Mode           VARCHAR(100)     = 'TEST'
    ,   @Logging        SMALLINT         = 1
    ,   @Run_UUID       UNIQUEIDENTIFIER = NULL
    ,   @Run_Inserts    BIGINT OUT
    ,   @Run_Updates    BIGINT OUT
    ,   @Run_Deletes    BIGINT OUT
)
AS
BEGIN
        DECLARE @My_Inserts BIGINT = 0;
        DECLARE @My_Updates BIGINT = 0;
        DECLARE @My_Deletes BIGINT = 0;
        SET NOCOUNT ON;
        BEGIN TRY
                --*********************************
                --****  Procedure logic starts ****
                --*********************************

                DROP TABLE IF EXISTS [Gold].[Fact_Lapsed_Patients];

                CREATE TABLE [Gold].[Fact_Lapsed_Patients] (
                        [pk_Lapsed_Patient]       BIGINT IDENTITY NOT NULL,
                        [Tenant_ID]               INT             NOT NULL,
                        [bk_Patient_ID]           INT             NOT NULL,
                        [fk_Patient]              BIGINT          NOT NULL,
                        [fk_Practitioner]         BIGINT          NOT NULL,
                        [fk_Practice_Site]        BIGINT          NOT NULL,
                        [fk_Payment_Plan]         BIGINT          NOT NULL,
                        [fk_Date_Lapsed]          BIGINT          NOT NULL,
                        [Lapsed_Type]             VARCHAR(30)     NULL,
                        [Lapsed_Reason]           VARCHAR(255)    NULL,
                        [Lapsed_Date]             DATE            NULL,
                        [Lapsed_Patient_Count]    INT             NOT NULL,
                        [DW_Created_At]           DATETIME2(3)    NOT NULL
                );

                INSERT INTO [Gold].[Fact_Lapsed_Patients]
                        (Tenant_ID, bk_Patient_ID, fk_Patient, fk_Practitioner, fk_Practice_Site,
                         fk_Payment_Plan, fk_Date_Lapsed, Lapsed_Type, Lapsed_Reason, Lapsed_Date,
                         Lapsed_Patient_Count, DW_Created_At)
                SELECT  p.Tenant_ID, p.Patient_ID, p.pk_Patient,
                        ISNULL(dpr.pk_Practitioner, -1),
                        ISNULL(dps.pk_Practice_Site, -1),
                        ISNULL(dpp.pk_Payment_Plan, -1),
                        ISNULL(p.fk_Date_Lapsed, -1),
                        p.Lapsed_Type, p.Lapsed_Reason, p.Lapsed_Date,
                        1, SYSUTCDATETIME()
                FROM    [Gold].[Dim_Patients] p
                LEFT JOIN [Gold].[Dim_Practitioners]  dpr ON dpr.Tenant_ID = p.Tenant_ID AND dpr.Practitioner_ID = p.Dentist_Practitioner_ID
                LEFT JOIN [Gold].[Dim_Practice_Sites] dps ON dps.Tenant_ID = p.Tenant_ID AND dps.Site_ID        = p.Site_ID
                LEFT JOIN [Gold].[Dim_Payment_Plans]  dpp ON dpp.Tenant_ID = p.Tenant_ID AND dpp.Payment_Plan_ID = p.Payment_Plan_ID
                WHERE   p.Lapsed_Type IS NOT NULL
                  AND   p.pk_Patient > 0;

                SET @My_Inserts = @@ROWCOUNT;

                --*********************************
                --****  Procedure logic ends   ****
                --*********************************

        END TRY

        BEGIN CATCH
                THROW;
        END CATCH;

        SET @Run_Inserts = @My_Inserts;
        SET @Run_Updates = @My_Updates;
        SET @Run_Deletes = @My_Deletes;

END
GO
