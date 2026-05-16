--------------------------------------------------------------------
--  Stored Procedure :  Bronze.usp_Load_All
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Added 11 new Bronze entity load procedures
--    *05     16/05/2026  AIH Add Audit ETL logging; add @Logging, @Run_UUID, @Run_Inserts/Updates/Deletes params; accumulate totals from children
--  To Run			 :   DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Bronze].[usp_Load_All] @Tenant_ID=1, @Full_Refresh=1, @Logging=1, @Run_UUID=NULL, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Bronze].[usp_Load_All]
GO
CREATE PROCEDURE [Bronze].[usp_Load_All]
(
      @Tenant_ID    INT
    , @Full_Refresh BIT              = 0
    , @Logging      SMALLINT         = 1
    , @Run_UUID     UNIQUEIDENTIFIER = NULL
    , @Run_Inserts  BIGINT OUT
    , @Run_Updates  BIGINT OUT
    , @Run_Deletes  BIGINT OUT
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @i  BIGINT = 0, @u  BIGINT = 0, @d  BIGINT = 0;
    DECLARE @ti BIGINT = 0, @tu BIGINT = 0, @td BIGINT = 0;

    BEGIN TRY

        EXEC Bronze.usp_Load_Practice                   @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Sites                      @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Users                      @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Practitioners              @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Payment_Plans              @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Treatments                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Patients                   @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Accounts                   @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Appointments               @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Invoices                   @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Invoice_Items              @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Payments                   @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Treatment_Plans            @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Treatment_Plan_Items       @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Recalls                    @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Practitioner_Diary_Entries @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Treatment_Categories       @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Acquisition_Sources        @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Cancellation_Reasons       @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Waiting_Lists              @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Sundries                   @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Contracts                  @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Fees                       @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Practitioner_Diary_Breaks  @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_NHS_Claims                 @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Patient_Stats              @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Payment_Allocations        @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Payment_Explanations       @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Treatment_Appointments     @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

        EXEC Bronze.usp_Load_Patient_Referrals          @Tenant_ID=@Tenant_ID, @Full_Refresh=@Full_Refresh, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
        SET @ti+=@i; SET @tu+=@u; SET @td+=@d;

    END TRY
    BEGIN CATCH THROW; END CATCH;

    SET @Run_Inserts = @ti;
    SET @Run_Updates = @tu;
    SET @Run_Deletes = @td;
END
GO
