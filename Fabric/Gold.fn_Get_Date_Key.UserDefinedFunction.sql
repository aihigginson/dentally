/****** Object:  UserDefinedFunction [Gold].[fn_Get_Date_Key]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


DROP FUNCTION IF EXISTS [Gold].[fn_Get_Date_Key]
GO
CREATE FUNCTION [Gold].[fn_Get_Date_Key] (@dt DATE)
RETURNS INT
AS
BEGIN
    DECLARE @key INT;

    SET @key = DATEDIFF(d,'19991231',@dt)

    RETURN @key;
END
GO
