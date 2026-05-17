--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Populate_Process_Dependencies
--  Author           :  AIH
--  Initital Date    :  17/05/2026
--  History          :
--    *01     17/05/2026  AIH Initial Release
--  To Run           :   EXEC Audit.usp_Populate_Process_Dependencies
--  How it works     :
--    Uses sys.sql_expression_dependencies to discover which tables each SP
--    references. Two SPs are linked when they both reference the same table
--    in the same schema — one writing to it, one reading from it.
--      Bronze SP  → Bronze table ← Silver SP   => Bronze→Silver dependency
--      Silver SP  → Silver table ← Gold SP     => Silver→Gold dependency
--      Gold F/D SP→ Gold table   ← Gold Agg SP => Gold→Aggregate dependency
--    Each discovered pair is matched to Process_Config via Process_Name
--    so only SPs registered in Process_Config are included.
---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS [Audit].[usp_Populate_Process_Dependencies]
GO
CREATE PROCEDURE [Audit].[usp_Populate_Process_Dependencies]
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY

        DELETE FROM Audit.Process_Dependency;

        -- ── Bronze SPs → Silver SPs ───────────────────────────────────────────
        -- A Bronze SP and a Silver SP are linked when they both reference the
        -- same Bronze table: the Bronze SP writes to it; the Silver SP reads from it.
        INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
        SELECT DISTINCT
              b_pc.Process_Code
            , s_pc.Process_Code
            , 'DATA'
            , 1
            , 1
        FROM    sys.sql_expression_dependencies AS b_dep
        INNER JOIN sys.objects  AS b_sp      ON b_sp.object_id      = b_dep.referencing_id AND b_sp.type  = 'P'
        INNER JOIN sys.schemas  AS b_sp_sch  ON b_sp_sch.schema_id  = b_sp.schema_id       AND b_sp_sch.name = 'Bronze'
        INNER JOIN sys.objects  AS b_tbl     ON b_tbl.object_id     = b_dep.referenced_id  AND b_tbl.type = 'U'
        INNER JOIN sys.schemas  AS b_tbl_sch ON b_tbl_sch.schema_id = b_tbl.schema_id      AND b_tbl_sch.name = 'Bronze'
        -- Silver SP that also references the same Bronze table
        INNER JOIN sys.sql_expression_dependencies AS s_dep ON s_dep.referenced_id = b_dep.referenced_id
        INNER JOIN sys.objects  AS s_sp      ON s_sp.object_id      = s_dep.referencing_id AND s_sp.type  = 'P'
        INNER JOIN sys.schemas  AS s_sp_sch  ON s_sp_sch.schema_id  = s_sp.schema_id       AND s_sp_sch.name = 'Silver'
        -- Match to Process_Config by qualified SP name
        INNER JOIN Audit.Process_Config AS b_pc ON b_pc.Process_Name = b_sp_sch.name + '.' + b_sp.name
        INNER JOIN Audit.Process_Config AS s_pc ON s_pc.Process_Name = s_sp_sch.name + '.' + s_sp.name;

        DECLARE @Bronze_Silver INT = @@ROWCOUNT;

        -- ── Silver SPs → Gold SPs ─────────────────────────────────────────────
        -- A Silver SP and a Gold SP are linked when they both reference the
        -- same Silver table.
        INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
        SELECT DISTINCT
              s_pc.Process_Code
            , g_pc.Process_Code
            , 'DATA'
            , 2
            , 1
        FROM    sys.sql_expression_dependencies AS s_dep
        INNER JOIN sys.objects  AS s_sp      ON s_sp.object_id      = s_dep.referencing_id AND s_sp.type  = 'P'
        INNER JOIN sys.schemas  AS s_sp_sch  ON s_sp_sch.schema_id  = s_sp.schema_id       AND s_sp_sch.name = 'Silver'
        INNER JOIN sys.objects  AS s_tbl     ON s_tbl.object_id     = s_dep.referenced_id  AND s_tbl.type = 'U'
        INNER JOIN sys.schemas  AS s_tbl_sch ON s_tbl_sch.schema_id = s_tbl.schema_id      AND s_tbl_sch.name = 'Silver'
        -- Gold SP that also references the same Silver table
        INNER JOIN sys.sql_expression_dependencies AS g_dep ON g_dep.referenced_id = s_dep.referenced_id
        INNER JOIN sys.objects  AS g_sp      ON g_sp.object_id      = g_dep.referencing_id AND g_sp.type  = 'P'
        INNER JOIN sys.schemas  AS g_sp_sch  ON g_sp_sch.schema_id  = g_sp.schema_id       AND g_sp_sch.name = 'Gold'
        INNER JOIN Audit.Process_Config AS s_pc ON s_pc.Process_Name = s_sp_sch.name + '.' + s_sp.name
        INNER JOIN Audit.Process_Config AS g_pc ON g_pc.Process_Name = g_sp_sch.name + '.' + g_sp.name;

        DECLARE @Silver_Gold INT = @@ROWCOUNT;

        -- ── Gold Fact/Dim SPs → Gold Aggregate SPs ────────────────────────────
        -- A Gold Fact/Dim SP and a Gold Aggregate SP are linked when they both
        -- reference the same Gold table.
        INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
        SELECT DISTINCT
              gf_pc.Process_Code
            , ga_pc.Process_Code
            , 'DATA'
            , 3
            , 1
        FROM    sys.sql_expression_dependencies AS gf_dep
        INNER JOIN sys.objects  AS gf_sp      ON gf_sp.object_id      = gf_dep.referencing_id AND gf_sp.type  = 'P'
        INNER JOIN sys.schemas  AS gf_sp_sch  ON gf_sp_sch.schema_id  = gf_sp.schema_id       AND gf_sp_sch.name = 'Gold'
        INNER JOIN sys.objects  AS gf_tbl     ON gf_tbl.object_id     = gf_dep.referenced_id  AND gf_tbl.type = 'U'
        INNER JOIN sys.schemas  AS gf_tbl_sch ON gf_tbl_sch.schema_id = gf_tbl.schema_id      AND gf_tbl_sch.name = 'Gold'
        -- Gold Aggregate SP that also references the same Gold table
        INNER JOIN sys.sql_expression_dependencies AS ga_dep ON ga_dep.referenced_id = gf_dep.referenced_id
        INNER JOIN sys.objects  AS ga_sp      ON ga_sp.object_id      = ga_dep.referencing_id AND ga_sp.type  = 'P'
        INNER JOIN sys.schemas  AS ga_sp_sch  ON ga_sp_sch.schema_id  = ga_sp.schema_id       AND ga_sp_sch.name = 'Gold'
        INNER JOIN Audit.Process_Config AS gf_pc ON gf_pc.Process_Name = gf_sp_sch.name + '.' + gf_sp.name AND gf_pc.Process_Category_Code IN ('GOLD_FACT', 'GOLD_DIM')
        INNER JOIN Audit.Process_Config AS ga_pc ON ga_pc.Process_Name = ga_sp_sch.name + '.' + ga_sp.name AND ga_pc.Process_Category_Code = 'GOLD_AGG';

        DECLARE @Gold_Agg INT = @@ROWCOUNT;

        PRINT 'Process_Dependency populated:';
        PRINT '  Bronze -> Silver : ' + CAST(@Bronze_Silver AS VARCHAR);
        PRINT '  Silver -> Gold   : ' + CAST(@Silver_Gold   AS VARCHAR);
        PRINT '  Gold   -> Agg    : ' + CAST(@Gold_Agg      AS VARCHAR);
        PRINT '  Total            : ' + CAST(@Bronze_Silver + @Silver_Gold + @Gold_Agg AS VARCHAR);

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;
END
GO
