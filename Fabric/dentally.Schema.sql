IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dentally')
    EXEC('CREATE SCHEMA [dentally]')
GO