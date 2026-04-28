IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Audit')
    EXEC('CREATE SCHEMA [Audit]')
GO