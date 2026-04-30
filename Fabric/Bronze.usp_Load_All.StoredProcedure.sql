--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_All
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Added 11 new Bronze entity load procedures
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Bronze.usp_Load_All @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_All]
GO
CREATE PROCEDURE [Bronze].[usp_Load_All]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT = 0
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @i BIGINT = 0, @u BIGINT = 0, @d BIGINT = 0;

    BEGIN TRY

        EXEC Bronze.usp_Load_Practice                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Practice:                 ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Sites                    @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Sites:                    ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Users                    @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Users:                    ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Practitioners            @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Practitioners:            ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Payment_Plans            @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Payment_Plans:            ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Treatments               @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Treatments:               ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Patients                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Patients:                 ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Accounts                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Accounts:                 ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Appointments             @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Appointments:             ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Invoices                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Invoices:                 ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Invoice_Items            @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Invoice_Items:            ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Payments                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Payments:                 ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Treatment_Plans          @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Treatment_Plans:          ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Treatment_Plan_Items     @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Treatment_Plan_Items:     ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Recalls                  @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Recalls:                  ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Practitioner_Diary_Entries @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Practitioner_Diary:       ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Treatment_Categories    @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Treatment_Categories:     ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Acquisition_Sources     @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Acquisition_Sources:      ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Sundries                @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Sundries:                 ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Contracts               @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Contracts:                ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Fees                    @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Fees:                     ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Practitioner_Diary_Breaks @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Practitioner_Diary_Breaks:ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_NHS_Claims              @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'NHS_Claims:               ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Patient_Stats           @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Patient_Stats:            ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Payment_Allocations     @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Payment_Allocations:      ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Payment_Explanations    @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Payment_Explanations:     ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

        EXEC Bronze.usp_Load_Treatment_Appointments  @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        PRINT 'Treatment_Appointments:   ins=' + CAST(@i AS VARCHAR(20)) + '  upd=' + CAST(@u AS VARCHAR(20)) + '  del=' + CAST(@d AS VARCHAR(20));

    END TRY
    BEGIN CATCH THROW; END CATCH;
END
GO
