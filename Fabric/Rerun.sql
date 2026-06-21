
 DELETE Audit.Process_Execution_Log; 
 DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT; 
 DECLARE  @Tenant_ID   INT = 11, @Full_Refresh INT =1; 
  EXEC [Audit].[usp_Load_Bronze] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 /*SET  @Tenant_ID    = 12
  EXEC [Audit].[usp_Load_Bronze] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 SET  @Tenant_ID    = 13
  EXEC [Audit].[usp_Load_Bronze] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 SET  @Tenant_ID    = 14
  EXEC [Audit].[usp_Load_Bronze] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 */
 -- DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT; 
 EXEC [Audit].[usp_Load_All] @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
SELECT * FROM  Audit.Process_Execution_Log order by Start_Time; 
 

 --EXEC Meta.usp_Create_Gold_Views

 SELECT * FROM PBI._Appointments