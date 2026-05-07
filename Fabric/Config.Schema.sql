IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Config')
    EXEC('CREATE SCHEMA [Config]')
GO
