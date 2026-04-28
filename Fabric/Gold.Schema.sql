IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Gold')
    EXEC('CREATE SCHEMA [Gold]')
GO