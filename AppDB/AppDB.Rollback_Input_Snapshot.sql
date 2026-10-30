/* ============================================================================
   APPDB -- put Input.* back from a snapshot taken by AppDB.Backup_Input_Snapshot.sql.

   ==> SET @stamp AND @tables BEFORE RUNNING. IT WILL NOT GUESS EITHER. <== A rollback that picks
   its own snapshot is a rollback that can restore the wrong generation, and the wrong generation of
   Maple's targets is indistinguishable from someone having edited them.

       @stamp   the stamp the snapshot printed, e.g. '20261030_1530'
       @tables  comma-separated Input table names, or 'ALL'

   Restore only what you actually need. The thing that usually needs putting back is Targets, and
   rewriting nine other tables to get it is risk nobody asked for.

   ==> IT IS ALL OR NOTHING, PER TABLE. <== The DELETE and the INSERT commit together, so an
   interrupted rollback cannot leave a table holding half of each generation.

   ==> WHAT IT CANNOT DO. <== It restores ROWS, not SCHEMA. If the migration added a column, the
   snapshot has no value for it and the restored rows take its default -- fine for Client_ID and
   Level_Type, which are nullable by design. If the migration DROPPED or RETYPED a column the
   snapshot has, this refuses and says so: reverse the DDL first, or use Azure SQL's
   point-in-time restore, which brings back the whole database including its shape.
   ============================================================================ */
SET NOCOUNT ON;

DECLARE @stamp  VARCHAR(20)    = '';                 /* <-- REQUIRED, e.g. '20261030_1530' */
DECLARE @tables NVARCHAR(2000) = 'Targets';          /* <-- or 'ALL', or 'Targets,Roles' */

IF @stamp = ''
    THROW 51300, 'Set @stamp to the snapshot you mean. AppDB.Backup_Input_Snapshot.sql printed it.', 1;

/* ==> ONE BATCH, FROM HERE TO THE END. <== GO ends a batch and a variable does not survive it, so
   a GO anywhere below this point loses @stamp and @tables -- which is precisely how the first
   version of this script failed, before it had touched anything. */

/* ---- what has been asked for, and does it exist ------------------------- */
DROP TABLE IF EXISTS #want;
SELECT LTRIM(RTRIM(value)) AS table_
INTO   #want
FROM   STRING_SPLIT(@tables, ',')
WHERE  LTRIM(RTRIM(value)) <> '';

IF EXISTS (SELECT 1 FROM #want WHERE table_ = 'ALL')
BEGIN
    DELETE FROM #want;
    INSERT INTO #want (table_)
    SELECT t.name FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
    WHERE  s.name = 'Input';
END

DECLARE @missing VARCHAR(400);
SELECT @missing = STRING_AGG(w.table_, ', ')
FROM   #want w
WHERE  OBJECT_ID('Backup.' + w.table_ + '__' + @stamp) IS NULL;
IF @missing IS NOT NULL
BEGIN
    SET @missing = 'No snapshot ' + @stamp + ' for: ' + @missing
                 + '. Check the stamp, or list Backup.* to see what exists.';
    THROW 51301, @missing, 1;
END

/* ---- a column the snapshot has and the table no longer does is a STOP ---- */
/* The reverse -- a column the table has gained -- is fine: it takes its default, which is how
   Client_ID and Level_Type are meant to arrive on an older row. */
DECLARE @lost VARCHAR(1000);
SELECT @lost = STRING_AGG(x.msg, '; ')
FROM (
    SELECT w.table_ + '.' + b.COLUMN_NAME AS msg
    FROM   #want w
    JOIN   INFORMATION_SCHEMA.COLUMNS b
           ON b.TABLE_SCHEMA = 'Backup' AND b.TABLE_NAME = w.table_ + '__' + @stamp
    WHERE  NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS l
                       WHERE l.TABLE_SCHEMA = 'Input' AND l.TABLE_NAME = w.table_
                         AND l.COLUMN_NAME = b.COLUMN_NAME)
) x;
IF @lost IS NOT NULL
BEGIN
    SET @lost = 'REFUSING: the snapshot holds columns the live table no longer has (' + @lost
              + '). Reverse the schema change first, or use point-in-time restore.';
    THROW 51302, @lost, 1;
END

/* ---- restore, one table at a time, each in its own transaction ----------- */
DECLARE @t SYSNAME, @cols NVARCHAR(MAX), @sql NVARCHAR(MAX), @before INT, @after INT, @snap INT;
DECLARE @e VARCHAR(400);          -- declared once; a DECLARE inside the loop runs every pass

DECLARE todo CURSOR LOCAL FAST_FORWARD FOR SELECT table_ FROM #want ORDER BY table_;
OPEN todo;
FETCH NEXT FROM todo INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    /* Only the columns BOTH sides have, and never a computed one -- Node_Level and Node_Key are
       derived and recompute themselves on insert. */
    SET @cols = NULL;
    SELECT @cols = STRING_AGG(QUOTENAME(l.COLUMN_NAME), ', ') WITHIN GROUP (ORDER BY l.ORDINAL_POSITION)
    FROM   INFORMATION_SCHEMA.COLUMNS l
    JOIN   INFORMATION_SCHEMA.COLUMNS b
           ON b.TABLE_SCHEMA = 'Backup' AND b.TABLE_NAME = @t + '__' + @stamp
          AND b.COLUMN_NAME  = l.COLUMN_NAME
    WHERE  l.TABLE_SCHEMA = 'Input' AND l.TABLE_NAME = @t
      AND  COLUMNPROPERTY(OBJECT_ID('Input.' + @t), l.COLUMN_NAME, 'IsComputed') = 0;

    SET @sql = N'SELECT @b = (SELECT COUNT(*) FROM [Input].[' + @t + N']), '
             + N'       @s = (SELECT COUNT(*) FROM [Backup].[' + @t + N'__' + @stamp + N'])';
    EXEC sp_executesql @sql, N'@b INT OUT, @s INT OUT', @b = @before OUT, @s = @snap OUT;

    BEGIN TRANSACTION;
        SET @sql = N'DELETE FROM [Input].[' + @t + N']; '
                 + N'INSERT INTO [Input].[' + @t + N'] (' + @cols + N') '
                 + N'SELECT ' + @cols + N' FROM [Backup].[' + @t + N'__' + @stamp + N']';
        EXEC sp_executesql @sql;
    COMMIT TRANSACTION;

    SET @sql = N'SELECT @a = (SELECT COUNT(*) FROM [Input].[' + @t + N'])';
    EXEC sp_executesql @sql, N'@a INT OUT', @a = @after OUT;

    PRINT 'Input.' + @t + ': ' + CAST(@before AS VARCHAR(10)) + ' -> '
        + CAST(@after AS VARCHAR(10)) + ' (snapshot held ' + CAST(@snap AS VARCHAR(10)) + ')';

    IF @after <> @snap
    BEGIN
        SET @e = 'ROLLBACK FAILED on Input.' + @t + ': holds '
               + CAST(@after AS VARCHAR(10)) + ', snapshot had ' + CAST(@snap AS VARCHAR(10)) + '.';
        THROW 51303, @e, 1;
    END

    FETCH NEXT FROM todo INTO @t;
END
CLOSE todo;
DEALLOCATE todo;

DROP TABLE IF EXISTS #want;

/* ==> THE WAREHOUSE COPY IS NOW AHEAD OF THE TRUTH. <== Input.* in WH_Dentally is a full-refresh
   copy of this database, so after a rollback it still holds the rows that were just undone. Re-sync
   before anybody reads a report, or the screens will keep showing the thing you rolled back:

       python Scripts/run_appdb_sync.py          (or the appdb-sync container job)
       then rebuild Gold.Fact_Node_Targets and Gold.Aggregate_Period_Targets, and refresh the model.
   ------------------------------------------------------------------------ */
