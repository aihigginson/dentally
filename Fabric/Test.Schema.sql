IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Test')
    EXEC('CREATE SCHEMA [Test]')
GO
