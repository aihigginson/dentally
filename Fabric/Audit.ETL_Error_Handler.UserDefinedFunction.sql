/****** Object:  UserDefinedFunction [Audit].[ETL_Error_Handler]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP FUNCTION IF EXISTS [Audit].[ETL_Error_Handler]
GO
CREATE   FUNCTION [Audit].[ETL_Error_Handler] ()
RETURNS VARCHAR(4000)
AS
BEGIN
    DECLARE @Result          VARCHAR(1000)  = NULL;
    DECLARE @Err_Number      INT            = NULL;
    DECLARE @Err_Severity    INT            = NULL;
    DECLARE @Err_State       INT            = NULL;
    DECLARE @Err_Procedure   VARCHAR(200)   = NULL;
    DECLARE @Err_Message     VARCHAR(4000)  = NULL;
    DECLARE @Err_JSON        VARCHAR(4000)  = NULL;

    SELECT  @Err_Number      = ERROR_NUMBER(),
            @Err_Severity    = ERROR_SEVERITY(),
            @Err_State       = ERROR_STATE(),
            @Err_Procedure   = ERROR_PROCEDURE(),
            @Err_Message     = ERROR_MESSAGE();

    -- Build error JSON
    SELECT @Err_JSON = '{ "ErrNumber": '      + CONVERT(VARCHAR, ISNULL(@Err_Number, 0))
                     + ', "ErrSeverity": '    + CONVERT(VARCHAR, ISNULL(@Err_Severity, 0))
                     + ', "ErrState": '       + CONVERT(VARCHAR, ISNULL(@Err_State, 0))
                     + ', "ErrProcedure": "'  + ISNULL(@Err_Procedure, '.') + '"'
                     + ', "ErrMessage": "'    + ISNULL(@Err_Message, '.')   + '" }';

    RETURN @Err_JSON;
END;
GO
