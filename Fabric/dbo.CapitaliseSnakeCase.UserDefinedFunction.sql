/****** Object:  UserDefinedFunction [dbo].[CapitaliseSnakeCase]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP FUNCTION IF EXISTS [dbo].[CapitaliseSnakeCase]
GO
CREATE   FUNCTION [dbo].[CapitaliseSnakeCase] (@name SYSNAME)
RETURNS VARCHAR(400)
AS
BEGIN
    DECLARE @result VARCHAR(400) = '';
    DECLARE @token VARCHAR(200);
    DECLARE @pos INT = 1;

    -- Split by underscore
    WHILE LEN(@name) > 0
    BEGIN
        SET @pos = CHARINDEX('_', @name);

        IF @pos = 0
        BEGIN
            SET @token = @name;
            SET @name = '';
        END
        ELSE
        BEGIN
            SET @token = LEFT(@name, @pos - 1);
            SET @name = SUBSTRING(@name, @pos + 1, LEN(@name));
        END

        -- Apply special acronym rules
        SET @token = 
            CASE 
                WHEN LOWER(@token) = 'id'  THEN 'ID'
                WHEN LOWER(@token) = 'nhs' THEN 'NHS'
                WHEN LOWER(@token) = 'uda' THEN 'UDA'
                WHEN LOWER(@token) = 'uoa' THEN 'UOA'
                WHEN LOWER(@token) = 'sms' THEN 'SMS'
                WHEN LOWER(@token) = 'fte' THEN 'FTE'
                ELSE UPPER(LEFT(@token,1)) + LOWER(SUBSTRING(@token,2,200))
            END;

        SET @result = @result + @token + 
                      CASE WHEN LEN(@name) > 0 THEN '_' ELSE '' END;
    END

    RETURN @result;
END;
GO
