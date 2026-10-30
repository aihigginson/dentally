/* ============================================================================
   APPDB -- snapshot every Input.* table inside the database, before a migration.

   ==> THIS IS THE FAST ROLLBACK, NOT THE SAFE ONE. <== It is a copy in the same database, so it is
   instant to take and instant to restore from, and it dies with the database. AppDB/Backup_AppDB.py
   writes the off-box copy. TAKE BOTH. The order that matters is: files first, then this, then the
   migration -- because this one cannot survive the mistake it is most likely to be needed for.

   ==> NOTHING IS DROPPED AND NOTHING IS OVERWRITTEN. <== Each run stamps its own set of tables, so
   two runs on the same day are two snapshots and a re-run can never land on top of the one you are
   about to need. Clearing old ones is deliberate and manual; see the bottom of this file.

        Backup.Targets__20261030_1530
        Backup.Practitioner_Pay__20261030_1530
        ...

   Azure SQL's own point-in-time restore sits behind all of this -- AppDB-prod can be restored to
   any moment in the last seven days -- but a PITR restores the WHOLE database to a NEW name, which
   then has to be swapped in. That is the right tool for "the migration corrupted everything" and the
   wrong one for "put Maple's targets back".

   To run: AppDB_go against AppDB-prod. It prints the stamp it used -- KEEP IT, the rollback script
   takes it as a parameter.
   ============================================================================ */
SET NOCOUNT ON;

/* BACKUP is a reserved word, so the schema is bracketed everywhere it appears -- including here.
   Unbracketed it fails with "Incorrect syntax near the keyword 'Backup'". */
IF SCHEMA_ID('Backup') IS NULL
    EXEC('CREATE SCHEMA [Backup]');
GO

DECLARE @stamp  VARCHAR(20) = CONVERT(VARCHAR(8), SYSUTCDATETIME(), 112) + '_'
                            + REPLACE(CONVERT(VARCHAR(5), SYSUTCDATETIME(), 108), ':', '');
DECLARE @sql    NVARCHAR(MAX) = N'';
DECLARE @t      SYSNAME;
DECLARE @n      INT = 0;

PRINT 'snapshot stamp: ' + @stamp + '   <-- KEEP THIS, the rollback needs it';
PRINT '';

/* Driven off the catalogue, not a hand-kept list: a table added to Input and forgotten here is
   exactly the one nobody can get back. */
DECLARE tabs CURSOR LOCAL FAST_FORWARD FOR
    SELECT t.name
    FROM   sys.tables t
    JOIN   sys.schemas s ON s.schema_id = t.schema_id
    WHERE  s.name = 'Input'
    ORDER  BY t.name;

OPEN tabs;
FETCH NEXT FROM tabs INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    /* SELECT INTO copies data and types but no keys, defaults or computed columns -- which is what
       is wanted: a snapshot is a bag of rows, and a computed column would refuse to be written. */
    SET @sql = N'SELECT * INTO [Backup].[' + @t + N'__' + @stamp + N'] FROM [Input].[' + @t + N']';
    EXEC sp_executesql @sql;
    SET @n = @n + 1;
    FETCH NEXT FROM tabs INTO @t;
END
CLOSE tabs;
DEALLOCATE tabs;

PRINT CAST(@n AS VARCHAR(10)) + ' table(s) snapshotted.';
GO

/* ---- prove it, rather than assume it ------------------------------------ */
/* Every Input table must have a copy from the newest stamp, holding the same number of rows. A
   snapshot that silently missed a table is the failure mode this catches. */
DECLARE @latest VARCHAR(20);
SELECT @latest = MAX(RIGHT(t.name, 13))
FROM   sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE  s.name = 'Backup' AND t.name LIKE '%\_\_20%' ESCAPE '\';

DECLARE @chk NVARCHAR(MAX) = N'';
SELECT @chk = @chk + N'SELECT ''' + t.name + N''' AS table_, '
            + N'(SELECT COUNT(*) FROM [Input].[' + t.name + N']) AS live_, '
            + N'(SELECT COUNT(*) FROM [Backup].[' + t.name + N'__' + @latest + N']) AS snapshot_ '
            + N'UNION ALL '
FROM   sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE  s.name = 'Input';
SET @chk = LEFT(@chk, LEN(@chk) - LEN(N'UNION ALL ')) + N' ORDER BY table_';
EXEC sp_executesql @chk;
GO

/* ---- housekeeping, deliberately manual ----------------------------------
   Snapshots are small (AppDB-prod is a few hundred rows in total) so they cost nothing to keep.
   When a release has bedded in, list and drop a stamp by hand:

     SELECT s.name + '.' + t.name AS snapshot_, p.rows
     FROM   sys.tables t
     JOIN   sys.schemas s ON s.schema_id = t.schema_id
     JOIN   sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
     WHERE  s.name = 'Backup' ORDER BY t.name;

   Do NOT script a blanket DROP of the Backup schema. The whole point of a snapshot is that it
   outlives the confidence of the person who took it.
   ------------------------------------------------------------------------ */
