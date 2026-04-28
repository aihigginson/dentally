IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Bronze')
    EXEC('CREATE SCHEMA [Bronze]')
GO