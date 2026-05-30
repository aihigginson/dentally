
 DELETE Audit.Process_Execution_Log; 
 DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT; 
 DECLARE  @Tenant_ID   INT = 15, @Full_Refresh INT =1; 
  EXEC [Bronze].[usp_Load_All] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 /*SET  @Tenant_ID    = 12
  EXEC [Bronze].[usp_Load_All] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 SET  @Tenant_ID    = 13
  EXEC [Bronze].[usp_Load_All] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 SET  @Tenant_ID    = 14
  EXEC [Bronze].[usp_Load_All] @Tenant_ID = @Tenant_ID, @Full_Refresh = @Full_Refresh, @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
 */
 -- DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT; 
 EXEC [Audit].[usp_Load_All] @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
SELECT * FROM  Audit.Process_Execution_Log order by Start_Time; 
 