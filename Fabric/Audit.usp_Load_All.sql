/****** Object:  StoredProcedure [Audit].[usp_Load_All]    Script Date: 29/04/2026 09:43:39 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO




-- DELETE Audit.Process_Execution_Log; DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC [Audit].[usp_Load_All] @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
ALTER PROCEDURE [Audit].[usp_Load_All]
(
      @Mode          VARCHAR(100) ='TEST' 
    , @Logging       TINYINT      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT OUT
    , @Run_Updates   BIGINT OUT
    , @Run_Deletes   BIGINT OUT
)
AS
BEGIN
    BEGIN TRY   
/*    DECLARE    @Mode          VARCHAR(100) ='TEST' 
    , @Logging       TINYINT      = 1
    , @Run_UUID      UNIQUEIDENTIFIER = NULL
    , @Run_Inserts   BIGINT 
    , @Run_Updates   BIGINT 
    , @Run_Deletes   BIGINT ;*/
    -- Local counters
    DECLARE @My_Inserts BIGINT = 0;
    DECLARE @My_Updates BIGINT = 0;
    DECLARE @My_Deletes BIGINT = 0;    
    SET NOCOUNT ON;    

        --*********************************
        --**** Procedure logic starts  ****
        --*********************************
     DECLARE @Run_Process_Name VARCHAR(1000) = 'Audit.usp_Load_All'
           , @Run_Process_Options  VARCHAR(1000) = 'TEST'
           , @Parent_Run_UUID VARCHAR(36) = @Run_UUID  
           , @Process_Type VARCHAR(50) = 'PROCEDURE'
           , @Process_Code  VARCHAR(100)  = 'GOLD_LOAD_ALL'
        
/*
================================================================================
  EXECUTION SCRIPT
  ─────────────────────────────────────────────────────────────────────────────
  Calls every implemented procedure in an order that respects logical
  dependencies (reference/lookup tables first, transactional tables last).
  Each step is wrapped in a TRY/CATCH so a single failure is logged without
  halting the rest of the load.
================================================================================
*/

DECLARE @Step       nvarchar(100);
DECLARE @Start  datetime2(3);
DECLARE @Msg        nvarchar(500);

-- ── Reference / lookup tables ────────────────────────────────────────────────
    EXEC [Audit].[ETL_Start_Run] @Run_Process_Name, @Run_Process_Options, @Run_UUID OUT, @Parent_Run_UUID, @Process_Type

    SET @Parent_Run_UUID = @Run_UUID

    
    SET @Step = 'Bronze_Accounts';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';


    SET @Step = 'Bronze_Appointments';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';


    SET @Step = 'Bronze_Invoices';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Invoice_Items';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Patients';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Payments';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Payment_Plans';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Practitioners';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Practitioner_Diary';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Recalls';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Sites';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Treatments';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Treatment_Plans';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Treatment_Plan_Items';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Bronze_Users';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '  + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';


    SET @Step = 'Acquisition_Sources';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
  --  EXEC Silver.usp_Load_Acquisition_Sources @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Treatment_Categories';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Treatment_Categories @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Payment_Plans';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Payment_Plans @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Practice';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Practice @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Sites';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Sites @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Users';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Users @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Practitioners';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Practitioners @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Practitioner_Diary';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Practitioner_Diary @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Practitioner_Diary_Breaks';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Practitioner_Diary_Breaks @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    -- ── Core patient & financial tables ──────────────────────────────────────────

    SET @Step = 'Patients';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Patients @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Accounts';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Accounts @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Contracts';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Contracts @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';

    SET @Step = 'Appointments';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Appointments @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
   SET @Step = 'Recalls';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Recalls @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Patient_Stats';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Patient_Stats @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    -- ── Treatment hierarchy ───────────────────────────────────────────────────────

    SET @Step = 'Treatments';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Treatments @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Fees';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Fees @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Treatment_Plans';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Treatment_Plans @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Treatment_Plan_Items';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Treatment_Plan_Items @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';


    SET @Step = 'Treatment_Appointments';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Treatment_Appointments @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
      -- ── Financial / invoicing ─────────────────────────────────────────────────────

    SET @Step = 'Invoices';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Invoices @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Invoice_Items';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Invoice_Items @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Payments';
    SET @Start = SYSUTCDATETIME();    
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Payments @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    SET @Step = 'Payment_Explanations';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Payment_Explanations @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  
    SET @Step = 'Payment_Allocations';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Payment_Allocations @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    -- ── NHS ───────────────────────────────────────────────────────────────────────

    SET @Step = 'Nhs_Claims';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Nhs_Claims @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
  

    -- ── Sundries ──────────────────────────────────────────────────────────────────

    SET @Step = 'Sundries';
    SET @Start = SYSUTCDATETIME();
    SET @Process_Code = 'SILVER_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Silver.usp_Load_Sundries @Mode=@Mode, @Logging=@Logging, @Run_UUID=@Run_UUID, @Run_Inserts=@My_Inserts OUT, @Run_Updates=@My_Updates OUT, @Run_Deletes=@My_Deletes OUT
    IF @Mode='TEST' PRINT @Step + ' completed in '
    + CAST(DATEDIFF(MILLISECOND, @Start, SYSUTCDATETIME()) AS nvarchar) + ' ms';
 
 
    -- ---- DIMENSIONS (load before facts) ----

    SET @Step = 'Dim_Date';           SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Gold.usp_Load_Dim_Users @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT

    SET @Step = 'Dim_Users';           SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Gold.usp_Load_Dim_Users @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT

    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Payment_Plans';   SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID
 -- EXEC Gold.usp_Load_Dim_Payment_Plans  @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Practice_Sites';  SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Dim_Practice_Sites @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Practitioners';   SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Dim_Practitioners @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT   
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Patients';        SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Dim_Patients @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Accounts';        SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Dim_Accounts @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Treatments';      SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Dim_Treatments @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT


    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Dim_Treatment_Plans'; SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Dim_Treatment_Plans @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    -- ---- FACTS ----

    SET @Step = 'Fact_Treatment_Plan_Items'; SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Treatment_Plan_Items @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Fact_Invoice_Items';  SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Invoice_Items @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Fact_Treatment_Appointments'; SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Treatment_Appointments @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';
    
    SET @Step = 'Fact_Practitioner_Diaries'; SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Practitioner_Diaries @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Fact_Contracts';      SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Contracts @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Fact_Appointments';   SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Appointments @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    SET @Step = 'Fact_Recalls';        SET @Start = GETDATE();
    SET @Process_Code = 'GOLD_'+UPPER(@Step)
    EXEC Audit.ETL_Run_Process @Process_Code ,@Parent_Run_UUID    
 -- EXEC Gold.usp_Load_Fact_Recalls @Run_Inserts=@My_Inserts, @Run_Updates=@My_Updates, @Run_Deletes=@My_Deletes OUT
    IF @Mode ='TEST' PRINT @Step + ' completed in ' + CAST(DATEDIFF(ms,@Start,GETDATE()) AS VARCHAR) + 'ms';

    PRINT 'Audit.usp_Load_All completed at ' + CONVERT(VARCHAR, GETDATE(), 120);
    EXEC [Audit].[ETL_Finish_Run] @Run_UUID, 'SUCCEEDED',0,0,0,'Success',''

        --*********************************
        --**** Procedure logic ends    ****
        --*********************************
    END TRY

    

    BEGIN CATCH
        THROW;
    END CATCH

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes  

END
GO


