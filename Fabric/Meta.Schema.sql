IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Meta')
    EXEC('CREATE SCHEMA [Meta]')
GO