--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Fact_NHS_Claims] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Fact_NHS_Claims
--  Author           :  AIH
--  Initital Date    :  03/06/2026
--  History          :
--    *01     03/06/2026  AIH Initial Release
--  To Run           :   DECLARE  @Run_Inserts BIGINT, @Run_Updates BIGINT, @Run_Deletes BIGINT; EXEC Gold.usp_Load_Fact_NHS_Claims @Run_Inserts=@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT, @Run_Deletes=@Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Gold].[usp_Load_Fact_NHS_Claims]    Script Date: 03/06/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Fact_NHS_Claims]
GO
CREATE PROCEDURE [Gold].[usp_Load_Fact_NHS_Claims]
(
      @Mode          VARCHAR(100)     = 'TEST'
    , @Logging       smallint         = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY
        --*********************************
        --**** Procedure logic starts  ****
        --*********************************

        SELECT
            nc.Tenant_ID,
            nc.NHS_Claim_ID                                             AS bk_NHS_Claim_ID,

            ISNULL(dpat.pk_Patient, -1)                                 AS fk_Patient,
            ISNULL(dpr.pk_Practitioner, -1)                             AS fk_Practitioner,
            ISNULL(dtp.pk_Treatment_Plan, -1)                           AS fk_Treatment_Plan,
            ISNULL(dps.pk_Practice_Site, -1)                            AS fk_Practice_Site,
            ISNULL(dnc.pk_NHS_Contract, -1)                             AS fk_NHS_Contract,

            dd_sub.pk_Date                                              AS fk_Date_Submitted,
            dd_app.pk_Date                                              AS fk_Date_Approval,

            NULLIF(TRIM(nc.Claim_Status), '')                           AS Claim_Status,
            nc.Sequence_Number,
            NULLIF(TRIM(nc.UDA_Band), '')                               AS UDA_Band,
            nc.Ortho,
            nc.Continuation_Part_Number,
            NULLIF(TRIM(nc.Status_Comments), '')                        AS Status_Comments,

            CAST(ISNULL(nc.Expected_UDA, 0)              AS DECIMAL(18,4)) AS Expected_UDA,
            CAST(ISNULL(nc.Awarded_UDA, 0)               AS DECIMAL(18,4)) AS Awarded_UDA,
            CAST(ISNULL(nc.Patient_Charge, 0)            AS DECIMAL(18,4)) AS Patient_Charge,
            CAST(ISNULL(nc.Dentist_Charge, 0)            AS DECIMAL(18,4)) AS Dentist_Charge,
            CAST(ISNULL(nc.Awarded_Dentist_Charge, 0)    AS DECIMAL(18,4)) AS Awarded_Dentist_Charge,
            CAST(ISNULL(nc.NI_Calculated_Dentist_Fee, 0) AS DECIMAL(18,4)) AS NI_Calculated_Dentist_Fee,
            CAST(ISNULL(nc.NI_Calculated_Patient_Fee, 0) AS DECIMAL(18,4)) AS NI_Calculated_Patient_Fee,
            CAST(ISNULL(nc.SCOT_Amount_Authorised, 0)    AS DECIMAL(18,4)) AS SCOT_Amount_Authorised,
            CAST(ISNULL(nc.SCOT_Amount_Expected, 0)      AS DECIMAL(18,4)) AS SCOT_Amount_Expected

        INTO #src
        FROM Silver.NHS_Claims nc
        LEFT JOIN Gold.Dim_Patients dpat        ON dpat.Patient_ID      = nc.Patient_ID          AND dpat.Tenant_ID = nc.Tenant_ID
        LEFT JOIN Gold.Dim_Practitioners dpr    ON dpr.Practitioner_ID  = nc.Practitioner_ID     AND dpr.Tenant_ID  = nc.Tenant_ID
        LEFT JOIN Gold.Dim_Treatment_Plans dtp  ON dtp.Treatment_Plan_ID = nc.Treatment_Plan_ID  AND dtp.Tenant_ID  = nc.Tenant_ID
        LEFT JOIN Gold.Dim_Practice_Sites dps   ON dps.Site_ID           = NULLIF(TRIM(nc.Site_ID), '')      AND dps.Tenant_ID = nc.Tenant_ID
        LEFT JOIN Gold.Dim_NHS_Contracts dnc    ON dnc.bk_Contract_ID   = NULLIF(TRIM(nc.Contract_ID), '')  AND dnc.Tenant_ID = nc.Tenant_ID
        LEFT JOIN Gold.Dim_Date dd_sub          ON dd_sub.Full_Date     = nc.Submitted_Date
        LEFT JOIN Gold.Dim_Date dd_app          ON dd_app.Full_Date     = nc.Approval_Date
        WHERE nc.NHS_Claim_ID IS NOT NULL;

        -- Remove rows no longer in source
        DELETE tgt
        FROM Gold.Fact_NHS_Claims tgt
        WHERE NOT EXISTS (SELECT 1 FROM #src WHERE bk_NHS_Claim_ID = tgt.bk_NHS_Claim_ID AND Tenant_ID = tgt.Tenant_ID);
        SET @My_Deletes = @@ROWCOUNT;

        -- Update changed rows
        UPDATE tgt SET
            fk_Patient                  = src.fk_Patient,
            fk_Practitioner             = src.fk_Practitioner,
            fk_Treatment_Plan           = src.fk_Treatment_Plan,
            fk_Practice_Site            = src.fk_Practice_Site,
            fk_NHS_Contract             = src.fk_NHS_Contract,
            fk_Date_Submitted           = src.fk_Date_Submitted,
            fk_Date_Approval            = src.fk_Date_Approval,
            Claim_Status                = src.Claim_Status,
            Sequence_Number             = src.Sequence_Number,
            UDA_Band                    = src.UDA_Band,
            Ortho                       = src.Ortho,
            Continuation_Part_Number    = src.Continuation_Part_Number,
            Status_Comments             = src.Status_Comments,
            Expected_UDA                = src.Expected_UDA,
            Awarded_UDA                 = src.Awarded_UDA,
            Patient_Charge              = src.Patient_Charge,
            Dentist_Charge              = src.Dentist_Charge,
            Awarded_Dentist_Charge      = src.Awarded_Dentist_Charge,
            NI_Calculated_Dentist_Fee   = src.NI_Calculated_Dentist_Fee,
            NI_Calculated_Patient_Fee   = src.NI_Calculated_Patient_Fee,
            SCOT_Amount_Authorised      = src.SCOT_Amount_Authorised,
            SCOT_Amount_Expected        = src.SCOT_Amount_Expected,
            DW_Updated_At               = SYSUTCDATETIME()
        FROM Gold.Fact_NHS_Claims tgt
        INNER JOIN #src src ON tgt.bk_NHS_Claim_ID = src.bk_NHS_Claim_ID AND tgt.Tenant_ID = src.Tenant_ID
        WHERE HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(tgt.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_NHS_Contract] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Submitted] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[fk_Date_Approval] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Claim_Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Sequence_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Ortho] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Continuation_Part_Number] AS VARCHAR(500)), ''),
           ISNULL(LEFT(tgt.[Status_Comments], 500), ''),
           ISNULL(CAST(tgt.[Expected_UDA] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Awarded_UDA] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Patient_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Dentist_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[Awarded_Dentist_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NI_Calculated_Dentist_Fee] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[NI_Calculated_Patient_Fee] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[SCOT_Amount_Authorised] AS VARCHAR(500)), ''),
           ISNULL(CAST(tgt.[SCOT_Amount_Expected] AS VARCHAR(500)), '')
           ))
           <> HASHBYTES('SHA2_256', CONCAT_WS(CHAR(0),
           ISNULL(CAST(src.[fk_Patient] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practitioner] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Treatment_Plan] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Practice_Site] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_NHS_Contract] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Submitted] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[fk_Date_Approval] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Claim_Status] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Sequence_Number] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[UDA_Band] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Ortho] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Continuation_Part_Number] AS VARCHAR(500)), ''),
           ISNULL(LEFT(src.[Status_Comments], 500), ''),
           ISNULL(CAST(src.[Expected_UDA] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Awarded_UDA] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Patient_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Dentist_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[Awarded_Dentist_Charge] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NI_Calculated_Dentist_Fee] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[NI_Calculated_Patient_Fee] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[SCOT_Amount_Authorised] AS VARCHAR(500)), ''),
           ISNULL(CAST(src.[SCOT_Amount_Expected] AS VARCHAR(500)), '')
           ));
        SET @My_Updates = @@ROWCOUNT;

        -- Insert new rows
        INSERT INTO Gold.Fact_NHS_Claims (
            Tenant_ID, bk_NHS_Claim_ID,
            fk_Patient, fk_Practitioner, fk_Treatment_Plan, fk_Practice_Site, fk_NHS_Contract,
            fk_Date_Submitted, fk_Date_Approval,
            Claim_Status, Sequence_Number, UDA_Band,
            Ortho, Continuation_Part_Number, Status_Comments,
            Expected_UDA, Awarded_UDA, Patient_Charge, Dentist_Charge,
            Awarded_Dentist_Charge, NI_Calculated_Dentist_Fee, NI_Calculated_Patient_Fee,
            SCOT_Amount_Authorised, SCOT_Amount_Expected,
            DW_Created_At, DW_Updated_At
        )
        SELECT
            src.Tenant_ID, src.bk_NHS_Claim_ID,
            src.fk_Patient, src.fk_Practitioner, src.fk_Treatment_Plan, src.fk_Practice_Site, src.fk_NHS_Contract,
            src.fk_Date_Submitted, src.fk_Date_Approval,
            src.Claim_Status, src.Sequence_Number, src.UDA_Band,
            src.Ortho, src.Continuation_Part_Number, src.Status_Comments,
            src.Expected_UDA, src.Awarded_UDA, src.Patient_Charge, src.Dentist_Charge,
            src.Awarded_Dentist_Charge, src.NI_Calculated_Dentist_Fee, src.NI_Calculated_Patient_Fee,
            src.SCOT_Amount_Authorised, src.SCOT_Amount_Expected,
            SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src src
        WHERE NOT EXISTS (SELECT 1 FROM Gold.Fact_NHS_Claims tgt WHERE tgt.bk_NHS_Claim_ID = src.bk_NHS_Claim_ID AND tgt.Tenant_ID = src.Tenant_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************

    END TRY

    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes

END
GO
