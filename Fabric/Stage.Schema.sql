IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Stage')
    EXEC('CREATE SCHEMA [Stage]')
GO
