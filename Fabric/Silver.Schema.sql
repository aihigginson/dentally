IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Silver')
    EXEC('CREATE SCHEMA [Silver]')
GO