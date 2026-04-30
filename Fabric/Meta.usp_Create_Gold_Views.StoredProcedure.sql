--------------------------------------------------------------------
--  Stored Procedure :  Meta.usp_Create_Gold_Views
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Add PBI.[Security Users] view for RLS anchor
--  To Run			 :   DECLARE  @Run_Inserts   BIGINT, @Run_Updates   BIGINT , @Run_Deletes BIGINT;  EXEC Meta.usp_Create_Gold_Views @Run_Inserts =@Run_Inserts OUT, @Run_Updates=@Run_Updates OUT , @Run_Deletes = @Run_Deletes OUT
---------------------------------------------------------------------
/****** Object:  StoredProcedure [Meta].[usp_Create_Gold_Views]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Meta].[usp_Create_Gold_Views]
GO
CREATE   PROCEDURE [Meta].[usp_Create_Gold_Views]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL         VARCHAR(MAX);
    DECLARE @Row         INT;
    DECLARE @Max_Row     INT;
    DECLARE @TableName   VARCHAR(128);
    DECLARE @ViewName    VARCHAR(500);
    DECLARE @ViewBase    VARCHAR(500);
    DECLARE @ColumnList  VARCHAR(MAX);

    -- Drop all existing PBI views
    SELECT @SQL = STRING_AGG(
            'DROP VIEW ' + QUOTENAME(s.name) + '.' + QUOTENAME(v.name) + ';',
            CHAR(10)
        )
    FROM sys.views v
    JOIN sys.schemas s ON v.schema_id = s.schema_id
    WHERE s.name = 'PBI';

    IF @SQL IS NOT NULL AND @SQL <> ''
        EXEC (@SQL);

    -- Stage Gold tables with row numbers (no cursor needed)
    CREATE TABLE #Gold_Tables (
        Row_Num    INT          NOT NULL,
        Table_Name VARCHAR(128) NOT NULL
    );

    INSERT INTO #Gold_Tables (Row_Num, Table_Name)
    SELECT ROW_NUMBER() OVER (ORDER BY t.name), t.name
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = 'Gold';

    SET @Row     = 1;
    SET @Max_Row = (SELECT COUNT(*) FROM #Gold_Tables);

    WHILE @Row <= @Max_Row
    BEGIN
        SELECT @TableName = Table_Name FROM #Gold_Tables WHERE Row_Num = @Row;

        -- Determine view name based on table type
        SET @ViewBase = REPLACE(@TableName, '_', ' ');
        IF @TableName LIKE 'Fact_%'
            SET @ViewName = QUOTENAME(REPLACE(@ViewBase, 'Fact ', '_'));
        ELSE IF @TableName LIKE 'Dim_%'
            SET @ViewName = QUOTENAME('List ' + REPLACE(@ViewBase, 'Dim ', ''));
        ELSE
            SET @ViewName = QUOTENAME(@TableName);

        -- Build column list with space-friendly aliases
        SET @ColumnList = NULL;
        SELECT @ColumnList = STRING_AGG(
                QUOTENAME(c.name) + ' AS ' + QUOTENAME(REPLACE(c.name, '_', ' ')),
                ', '
            )
        FROM sys.columns c
        INNER JOIN sys.tables t ON c.object_id = t.object_id
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE t.name = @TableName
          AND s.name = 'Gold';

        SET @SQL = N'CREATE VIEW PBI.' + @ViewName + N' AS
SELECT ' + @ColumnList + N'
FROM Gold.' + QUOTENAME(@TableName) + N';';

        EXEC (@SQL);

        SET @Row = @Row + 1;
    END;

    DROP TABLE #Gold_Tables;

    -- Security lookup view (used as RLS anchor in Power BI)
    SET @SQL = N'CREATE VIEW PBI.[Application Users] AS
SELECT [User_UPN] AS [User UPN], [Tenant_ID] AS [Tenant ID]
FROM Security.Application_Users;';
    EXEC (@SQL);

END;

GO
