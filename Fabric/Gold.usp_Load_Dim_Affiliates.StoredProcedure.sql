--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Affiliates] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Affiliates
--  Author           :  AIH
--  Initial Date     :  24/09/2026
--  History          :
--    *01     24/09/2026  AIH  Initial Release (V182)
--  Notes:
--    Source : Billing.Affiliate (maintained by the Admin screen)
--    Pattern: Dim MERGE upsert -- pk_Affiliate is preserved so Fact_Affiliate_Payment_Lines
--             keeps pointing at the same partner across loads.
--    Practices_Introduced counts the tenants currently LINKED, which is a live figure and moves
--    when a link is changed. It is a convenience for the list, not an accounting number -- the
--    money always comes from the fact.
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Affiliates]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Affiliates]
(
      @Mode        VARCHAR(100)     = 'TEST'
    , @Logging     smallint         = 1
    , @Run_UUID    UNIQUEIDENTIFIER = NULL
    , @Run_Inserts BIGINT OUT
    , @Run_Updates BIGINT OUT
    , @Run_Deletes BIGINT OUT
)
AS
BEGIN
    DECLARE @My_Inserts BIGINT = 0, @My_Updates BIGINT = 0, @My_Deletes BIGINT = 0;
    SET NOCOUNT ON;
    BEGIN TRY

        SELECT a.Affiliate_ID,
               a.Email,
               a.Name,
               a.Commission_Pct,
               CAST(a.Created_At AS DATE) AS Created_Date,
               a.Notes,
               a.VAT_Number,
               a.Is_VAT_Registered,
               a.Self_Bill_Agreed_On,
               -- Payable only when the written agreement exists AND we know the VAT position.
               -- "Not registered" is a fine answer; "we never asked" is not, and a NULL cannot
               -- tell them apart -- so an unanswered VAT question blocks payment by design.
               CAST(CASE WHEN a.Self_Bill_Agreed_On IS NOT NULL
                          AND a.Is_VAT_Registered IS NOT NULL
                         THEN 1 ELSE 0 END AS BIT)          AS Can_Self_Bill,
               (SELECT COUNT(*) FROM [Billing].[Account_Billing] ab
                 WHERE ab.Affiliate_ID = a.Affiliate_ID) AS Practices_Introduced
        INTO #src
        FROM [Billing].[Affiliate] a;

        UPDATE tgt
           SET Affiliate_Email        = s.Email,
               Affiliate_Name         = s.Name,
               Standard_Commission_Pct= s.Commission_Pct,
               Practices_Introduced   = s.Practices_Introduced,
               Created_Date           = s.Created_Date,
               Notes                  = s.Notes,
               VAT_Number             = s.VAT_Number,
               Is_VAT_Registered      = s.Is_VAT_Registered,
               Self_Bill_Agreed_On    = s.Self_Bill_Agreed_On,
               Can_Self_Bill          = s.Can_Self_Bill,
               DW_Updated_At          = SYSUTCDATETIME()
        FROM [Gold].[Dim_Affiliates] tgt
        JOIN #src s ON s.Affiliate_ID = tgt.bk_Affiliate_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Gold].[Dim_Affiliates]
            (pk_Affiliate, bk_Affiliate_ID, Affiliate_Email, Affiliate_Name,
             Standard_Commission_Pct, Practices_Introduced, Created_Date, Notes,
             VAT_Number, Is_VAT_Registered, Self_Bill_Agreed_On, Can_Self_Bill,
             Affiliate_Count, DW_Created_At, DW_Updated_At)
        SELECT ISNULL((SELECT MAX(pk_Affiliate) FROM [Gold].[Dim_Affiliates]), 0)
                 + ROW_NUMBER() OVER (ORDER BY s.Affiliate_ID),
               s.Affiliate_ID, s.Email, s.Name, s.Commission_Pct, s.Practices_Introduced,
               s.Created_Date, s.Notes,
               s.VAT_Number, s.Is_VAT_Registered, s.Self_Bill_Agreed_On, s.Can_Self_Bill,
               1, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM [Gold].[Dim_Affiliates] t
                           WHERE t.bk_Affiliate_ID = s.Affiliate_ID);
        SET @My_Inserts = @@ROWCOUNT;

        DROP TABLE #src;

    END TRY
    BEGIN CATCH
        THROW;
    END CATCH;

    SET @Run_Inserts = @My_Inserts
    SET @Run_Updates = @My_Updates
    SET @Run_Deletes = @My_Deletes
END
GO
