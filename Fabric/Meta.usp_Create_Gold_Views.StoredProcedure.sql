--------------------------------------------------------------------
--  Stored Procedure :  Meta.usp_Create_Gold_Views
--  Author           :  AIH
--  Initital Date    :  29/04/2026
--  History          :
--    *01     29/04/2026  AIH Initial Release
--    *02     29/04/2026  AIH Add PBI.[Security Users] view for RLS anchor
--    *03     09/05/2026  AIH Add WHERE Patient_ID IS NOT NULL on List Accounts to exclude -1 unknown row
--    *04     22/05/2026  AIH Exclude pk=-1 sentinel rows from List Patients and List Treatment Plans
--    *05     31/05/2026  AIH Add PBI.[_Appointments Sankey] custom view for Microsoft Sankey visual
--    *06     02/06/2026  AIH Add fk_Date_Start, fk_Practice_Site, fk_Practitioner to Sankey view for PBI slicer relationships
--    *07     14/06/2026  AIH Generate PBI views 1-1 from Gold VIEWS as well as tables. A Gold
--                            view vw_<X> supersedes table <X> (same PBI name), so processing
--                            (e.g. live time-derived columns) lives in the Gold view and the
--                            PBI view stays a purely cosmetic rename wrapper.
--    *08     15/06/2026  AIH Remove PBI.[_Appointments Sankey] (built from Delay/Next_Appointment/
--                            Current_State, which moved off the fact to DAX). To be rebuilt in DAX.
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
    DECLARE @TableName   VARCHAR(128);   -- entity name (drives the PBI view name)
    DECLARE @ObjectName  VARCHAR(128);   -- actual Gold object to SELECT FROM (table or view)
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

    -- Presentation sources = Gold tables + Gold views, generated 1-1 into the PBI
    -- layer. A Gold view named vw_<X> is the presentation source for table <X>:
    -- it maps to the SAME PBI name and SUPERSEDES the table (the table's own PBI
    -- view is skipped). This lets processing (e.g. live time-derived columns) live
    -- in a Gold view while the PBI view stays a purely cosmetic rename wrapper.
    CREATE TABLE #Sources (
        Row_Num     INT          NOT NULL,
        Object_Name VARCHAR(128) NOT NULL,   -- actual Gold object to SELECT FROM
        Entity_Name VARCHAR(128) NOT NULL    -- drives the PBI view name
    );

    INSERT INTO #Sources (Row_Num, Object_Name, Entity_Name)
    SELECT ROW_NUMBER() OVER (ORDER BY Object_Name), Object_Name, Entity_Name
    FROM (
        -- Gold tables NOT superseded by a vw_<table> override view
        SELECT t.name AS Object_Name, t.name AS Entity_Name
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name = 'Gold'
          AND NOT EXISTS (SELECT 1 FROM sys.views v
                          INNER JOIN sys.schemas sv ON v.schema_id = sv.schema_id
                          WHERE sv.name = 'Gold' AND v.name = 'vw_' + t.name)
        UNION ALL
        -- Gold views: vw_<X> drives entity <X>; any other Gold view maps by its own name
        SELECT v.name,
               CASE WHEN v.name LIKE 'vw[_]%' THEN SUBSTRING(v.name, 4, 128) ELSE v.name END
        FROM sys.views v
        INNER JOIN sys.schemas s ON v.schema_id = s.schema_id
        WHERE s.name = 'Gold'
          AND v.name <> 'vw_Dim_Date'   -- back-end-only per-tenant date helper; must NOT become PBI.[List Date]
    ) src;

    SET @Row     = 1;
    SET @Max_Row = (SELECT COUNT(*) FROM #Sources);

    WHILE @Row <= @Max_Row
    BEGIN
        SELECT @TableName = Entity_Name, @ObjectName = Object_Name
        FROM #Sources WHERE Row_Num = @Row;

        -- Determine PBI view name from the ENTITY name (table-type prefix)
        SET @ViewBase = REPLACE(@TableName, '_', ' ');
        IF @TableName LIKE 'Fact_%'
            SET @ViewName = QUOTENAME(REPLACE(@ViewBase, 'Fact ', '_'));
        ELSE IF @TableName LIKE 'Dim_%'
            SET @ViewName = QUOTENAME('List ' + REPLACE(@ViewBase, 'Dim ', ''));
        ELSE IF @TableName LIKE 'Aggregate_%'
            SET @ViewName = QUOTENAME('Aggregate ' + REPLACE(@ViewBase, 'Aggregate ', ''));
        ELSE
            SET @ViewName = QUOTENAME(@TableName);

        -- Entity-specific WHERE clauses (e.g. exclude DW unknown/-1 rows)
        DECLARE @WhereClause NVARCHAR(500) = N'';

        -- Build column list (space-friendly aliases) from the SOURCE object's columns
        -- (sys.columns covers both tables and views).
        SET @ColumnList = NULL;
        SELECT @ColumnList = STRING_AGG(
                QUOTENAME(c.name) + ' AS ' + QUOTENAME(REPLACE(c.name, '_', ' ')),
                ', '
            )
        FROM sys.columns c
        WHERE c.object_id = OBJECT_ID('Gold.' + @ObjectName);

        SET @SQL = N'CREATE VIEW PBI.' + @ViewName + N' AS
SELECT ' + @ColumnList + N'
FROM Gold.' + QUOTENAME(@ObjectName) + @WhereClause + N';';

        EXEC (@SQL);

        SET @Row = @Row + 1;
    END;

    DROP TABLE #Sources;

    -- Security lookup view (used as RLS anchor in Power BI)
    SET @SQL = N'CREATE VIEW PBI.[Application Users] AS
SELECT [User_UPN] AS [User UPN], [Tenant_ID] AS [Tenant ID]
FROM Security.Application_Users a JOIN Audit.Tenants t ON a.Client_ID = t.Client_ID;';
    EXEC (@SQL);

    -- NOTE: PBI.[_Appointments Sankey] removed (V008). It was built from the journey
    -- columns Delay / Next_Appointment / Current_State, which have moved off the fact
    -- table to DAX (computed from the appointment self-relationship + Recalls, with a
    -- hygiene toggle). The Sankey will be rebuilt from those DAX measures.

END;


GO
