--------------------------------------------------------------------
--  Stored Procedure :  Audit.usp_Populate_Process_Dependencies
--  Author           :  AIH
--  Initital Date    :  17/05/2026
--  History          :
--    *01     17/05/2026  AIH Initial Release - sys.sql_expression_dependencies
--    *02     17/05/2026  AIH Rewrite: sys.sql_modules + LIKE text scan
--                            (sql_expression_dependencies not supported in Fabric)
--  To Run           :   EXEC Audit.usp_Populate_Process_Dependencies
--  How it works     :
--    Reads every stored procedure's definition text via sys.sql_modules.
--    Two SPs are linked when one writes to a table (INTO Schema.Table)
--    and the other reads from the same table (any mention of Schema.Table).
--      Bronze SP writes Bronze.X  <-- Silver SP reads Bronze.X  => Bronze->Silver
--      Silver SP writes Silver.X  <-- Gold SP   reads Silver.X  => Silver->Gold
--      Gold F/D SP writes Gold.X  <-- Gold Agg  reads Gold.X   => Gold->Aggregate
--    Only SPs registered in Process_Config are included.
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
        -- Bronze SP writes to Bronze.X  (MERGE INTO / INSERT INTO Bronze.X)
        -- Silver SP reads from Bronze.X (any mention of Bronze.X in definition)
        INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
        SELECT DISTINCT
              b_pc.Process_Code
            , s_pc.Process_Code
            , 'DATA'
            , 1
            , 1
        FROM   sys.procedures  AS b_sp
        JOIN   sys.schemas     AS b_sch ON b_sch.schema_id = b_sp.schema_id AND b_sch.name = 'Bronze'
        JOIN   sys.sql_modules AS b_m   ON b_m.object_id   = b_sp.object_id
        -- Candidate link tables: every Bronze table
        CROSS JOIN (
            SELECT t.name AS tbl_name
            FROM   sys.tables  AS t
            JOIN   sys.schemas AS s ON s.schema_id = t.schema_id AND s.name = 'Bronze'
        ) AS bt
        -- Silver SPs
        JOIN   sys.procedures  AS s_sp  ON 1 = 1
        JOIN   sys.schemas     AS s_sch ON s_sch.schema_id = s_sp.schema_id AND s_sch.name = 'Silver'
        JOIN   sys.sql_modules AS s_m   ON s_m.object_id   = s_sp.object_id
        -- Both must be registered in Process_Config
        JOIN   Audit.Process_Config AS b_pc ON b_pc.Process_Name = b_sch.name + '.' + b_sp.name
        JOIN   Audit.Process_Config AS s_pc ON s_pc.Process_Name = s_sch.name + '.' + s_sp.name
        WHERE
            -- Bronze SP writes to the Bronze table
            UPPER(b_m.definition) LIKE '%INTO BRONZE.' + UPPER(bt.tbl_name) + '%'
            AND
            -- Silver SP references the same Bronze table
            UPPER(s_m.definition) LIKE '%BRONZE.' + UPPER(bt.tbl_name) + '%';

        DECLARE @Bronze_Silver INT = @@ROWCOUNT;

        -- ── Silver SPs → Gold SPs ─────────────────────────────────────────────
        -- Silver SP writes to Silver.X  (MERGE INTO / INSERT INTO Silver.X)
        -- Gold SP reads from Silver.X   (any mention of Silver.X in definition)
        INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
        SELECT DISTINCT
              s_pc.Process_Code
            , g_pc.Process_Code
            , 'DATA'
            , 2
            , 1
        FROM   sys.procedures  AS s_sp
        JOIN   sys.schemas     AS s_sch ON s_sch.schema_id = s_sp.schema_id AND s_sch.name = 'Silver'
        JOIN   sys.sql_modules AS s_m   ON s_m.object_id   = s_sp.object_id
        CROSS JOIN (
            SELECT t.name AS tbl_name
            FROM   sys.tables  AS t
            JOIN   sys.schemas AS s ON s.schema_id = t.schema_id AND s.name = 'Silver'
        ) AS st
        JOIN   sys.procedures  AS g_sp  ON 1 = 1
        JOIN   sys.schemas     AS g_sch ON g_sch.schema_id = g_sp.schema_id AND g_sch.name = 'Gold'
        JOIN   sys.sql_modules AS g_m   ON g_m.object_id   = g_sp.object_id
        JOIN   Audit.Process_Config AS s_pc ON s_pc.Process_Name = s_sch.name + '.' + s_sp.name
        JOIN   Audit.Process_Config AS g_pc ON g_pc.Process_Name = g_sch.name + '.' + g_sp.name
        WHERE
            UPPER(s_m.definition) LIKE '%INTO SILVER.' + UPPER(st.tbl_name) + '%'
            AND
            UPPER(g_m.definition) LIKE '%SILVER.' + UPPER(st.tbl_name) + '%';

        DECLARE @Silver_Gold INT = @@ROWCOUNT;

        -- ── Gold Fact/Dim SPs → Gold Aggregate SPs ────────────────────────────
        -- Gold Fact/Dim SP writes to Gold.X  (INSERT INTO Gold.X)
        -- Gold Agg SP reads from Gold.X      (any mention of Gold.X in definition)
        INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active)
        SELECT DISTINCT
              gf_pc.Process_Code
            , ga_pc.Process_Code
            , 'DATA'
            , 3
            , 1
        FROM   sys.procedures  AS gf_sp
        JOIN   sys.schemas     AS gf_sch ON gf_sch.schema_id = gf_sp.schema_id AND gf_sch.name = 'Gold'
        JOIN   sys.sql_modules AS gf_m   ON gf_m.object_id   = gf_sp.object_id
        CROSS JOIN (
            SELECT t.name AS tbl_name
            FROM   sys.tables  AS t
            JOIN   sys.schemas AS s ON s.schema_id = t.schema_id AND s.name = 'Gold'
        ) AS gt
        JOIN   sys.procedures  AS ga_sp  ON 1 = 1
        JOIN   sys.schemas     AS ga_sch ON ga_sch.schema_id = ga_sp.schema_id AND ga_sch.name = 'Gold'
        JOIN   sys.sql_modules AS ga_m   ON ga_m.object_id   = ga_sp.object_id
        -- Fact/Dim category filter on the writing SP
        JOIN   Audit.Process_Config AS gf_pc ON gf_pc.Process_Name = gf_sch.name + '.' + gf_sp.name
                                             AND gf_pc.Process_Category_Code IN ('GOLD_FACT', 'GOLD_DIM')
        -- Aggregate category filter on the reading SP
        JOIN   Audit.Process_Config AS ga_pc ON ga_pc.Process_Name = ga_sch.name + '.' + ga_sp.name
                                             AND ga_pc.Process_Category_Code = 'GOLD_AGG'
        WHERE
            UPPER(gf_m.definition) LIKE '%INTO GOLD.' + UPPER(gt.tbl_name) + '%'
            AND
            UPPER(ga_m.definition) LIKE '%GOLD.' + UPPER(gt.tbl_name) + '%';

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
