IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Input')
    EXEC('CREATE SCHEMA [Input]')
GO
