"""Generate Fabric/Input_Stage.*.Table.sql from the live AppDB schema.

Generated rather than hand-written so the staging shapes cannot drift from the source by a
transcription slip. Types are mapped to what the Fabric Warehouse actually supports.
"""
import io
import struct
import subprocess

import pyodbc

TABLES = ["Application_Users", "Access_Log", "Metric_Variance", "Plan_Capitation_Rate",
          "Practice_Config", "Practitioner_Pay", "Practitioner_Role", "Targets"]

OUT = r"C:\Users\aihig\OneDrive\Dentally\Code\Fabric"

HEADER = """-- Input_Stage.{t}
-- Landing copy of AppDB Input.{t}, written by the appdb-sync Container Apps Job.
--
-- WHY THIS EXISTS: AppDB moved off the Fabric capacity to Azure SQL (see AppDB/MIGRATION.md).
-- The Meta.usp_Sync_*_From_AppDB procs used to read [AppDB].[Input].[{t}] by three-part name,
-- which only resolves for a Fabric item in the same workspace. They now read this table instead,
-- and the job lands the rows here. Their MERGE logic is otherwise unchanged.
--
-- TRANSIENT. The job DELETEs and refills it every run; it is never the system of record and holds
-- no history. Truncating it loses nothing -- the next run restores it from AppDB.
--
-- Types match AppDB exactly, except where the Fabric Warehouse has no equivalent:
--   TINYINT -> SMALLINT (Practice_Config.FY_Start_Month). Values 1-12, so the widening is free.
--
-- No PK: the Fabric Warehouse does not enforce constraints, so declaring one would be decoration
-- that implies a guarantee the engine does not give. The source PKs are enforced in AppDB.
--
-- GENERATED from the live AppDB schema by Scripts/Generate_Input_Stage_DDL.py -- regenerate rather than
-- hand-edit if AppDB_Input_Schema.sql changes.
IF SCHEMA_ID('Input_Stage') IS NULL EXEC('CREATE SCHEMA Input_Stage');
GO
IF OBJECT_ID('Input_Stage.{t}') IS NULL
CREATE TABLE [Input_Stage].[{t}] (
{cols}
);
GO
"""


def fabric_type(dt, ln, p, s):
    dt = dt.lower()
    if dt == 'tinyint':
        return 'SMALLINT'                      # Fabric Warehouse has no TINYINT
    if dt in ('varchar', 'char'):
        size = 'MAX' if ln in (-1, None) else str(ln)
        return f'{dt.upper()}({size})'
    if dt == 'decimal':
        return f'DECIMAL({p},{s})'
    if dt == 'datetime2':
        return 'DATETIME2(3)'
    return dt.upper()


def main():
    out = subprocess.check_output(
        ['az', 'account', 'get-access-token', '--resource',
         'https://database.windows.net', '--query', 'accessToken', '-o', 'tsv'], shell=True)
    tb = out.decode().strip().encode('utf-16-le')
    ts = struct.pack(f'<I{len(tb)}s', len(tb), tb)
    cs = ('Driver={ODBC Driver 18 for SQL Server};Server=sql-analytically.database.windows.net,1433;'
          'Database=AppDB-dev;Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;')
    cur = pyodbc.connect(cs, attrs_before={1256: ts}, autocommit=True).cursor()

    for t in TABLES:
        cur.execute("""SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH,
                              NUMERIC_PRECISION, NUMERIC_SCALE, IS_NULLABLE
                       FROM INFORMATION_SCHEMA.COLUMNS
                       WHERE TABLE_SCHEMA='Input' AND TABLE_NAME=? ORDER BY ORDINAL_POSITION""", t)
        rows = cur.fetchall()
        width = max(len(r[0]) for r in rows) + 2
        lines = []
        for name, dt, ln, p, s, nul in rows:
            typ = fabric_type(dt, ln, p, s)
            null = 'NOT NULL' if nul == 'NO' else '    NULL'
            lines.append(f'    [{name}]{" " * (width - len(name))}{typ:16} {null}')
        body = ',\n'.join(lines)
        path = f'{OUT}\\Input_Stage.{t}.Table.sql'
        # UTF-16 LE with BOM -- the repo-wide SQL convention (CLAUDE.md)
        io.open(path, 'w', encoding='utf-16').write(HEADER.format(t=t, cols=body))
        print(f'wrote Input_Stage.{t}.Table.sql  ({len(rows)} columns)')


if __name__ == '__main__':
    main()
