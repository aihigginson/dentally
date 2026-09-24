--DECLARE @i BIGINT=0, @u BIGINT=0, @d BIGINT=0; EXEC [Gold].[usp_Load_Dim_Affiliate_Payments] @Mode='PROD', @Run_Inserts=@i OUT, @Run_Updates=@u OUT, @Run_Deletes=@d OUT;
--------------------------------------------------------------------
--  Stored Procedure :  Gold.usp_Load_Dim_Affiliate_Payments
--  Author           :  AIH
--  Initial Date     :  24/09/2026
--  History          :
--    *01     24/09/2026  AIH  Initial Release (V182)
--  Notes:
--    Source : Billing.Affiliate_Payout
--    Pattern: Dim MERGE upsert keyed on bk_Payout_ID.
--    fk_Affiliate resolves through Gold.Dim_Affiliates, so DIM ORDER MATTERS -- affiliates load
--    first, which the dependency generator enforces from the table references below.
---------------------------------------------------------------------
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

DROP PROCEDURE IF EXISTS [Gold].[usp_Load_Dim_Affiliate_Payments]
GO
CREATE PROCEDURE [Gold].[usp_Load_Dim_Affiliate_Payments]
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

        SELECT p.Payout_ID,
               da.pk_Affiliate                                   AS fk_Affiliate,
               [Gold].[fn_Get_Date_Key](p.Paid_At)               AS fk_Date_Paid,
               da.Affiliate_Email,
               da.Affiliate_Name,
               p.Year_Month,
               DATEFROMPARTS(p.Year_Month / 100, p.Year_Month % 100, 1) AS Month_Start,
               p.Amount,
               p.Paid_At,
               p.Reference,
               p.Notes
        INTO #src
        FROM [Billing].[Affiliate_Payout] p
        LEFT JOIN [Gold].[Dim_Affiliates] da ON da.bk_Affiliate_ID = p.Affiliate_ID;

        UPDATE tgt
           SET fk_Affiliate    = s.fk_Affiliate,
               fk_Date_Paid    = s.fk_Date_Paid,
               Affiliate_Email = s.Affiliate_Email,
               Affiliate_Name  = s.Affiliate_Name,
               Year_Month      = s.Year_Month,
               Month_Start     = s.Month_Start,
               Amount_Paid     = s.Amount,
               Paid_Date       = s.Paid_At,
               Reference       = s.Reference,
               Notes           = s.Notes,
               DW_Updated_At   = SYSUTCDATETIME()
        FROM [Gold].[Dim_Affiliate_Payments] tgt
        JOIN #src s ON s.Payout_ID = tgt.bk_Payout_ID;
        SET @My_Updates = @@ROWCOUNT;

        INSERT INTO [Gold].[Dim_Affiliate_Payments]
            (pk_Affiliate_Payment, bk_Payout_ID, fk_Affiliate, fk_Date_Paid, Affiliate_Email,
             Affiliate_Name, Year_Month, Month_Start, Amount_Paid, Paid_Date, Reference, Notes,
             Payment_Count, DW_Created_At, DW_Updated_At)
        SELECT ISNULL((SELECT MAX(pk_Affiliate_Payment) FROM [Gold].[Dim_Affiliate_Payments]), 0)
                 + ROW_NUMBER() OVER (ORDER BY s.Payout_ID),
               s.Payout_ID, s.fk_Affiliate, s.fk_Date_Paid, s.Affiliate_Email, s.Affiliate_Name,
               s.Year_Month, s.Month_Start, s.Amount, s.Paid_At, s.Reference, s.Notes,
               1, SYSUTCDATETIME(), SYSUTCDATETIME()
        FROM #src s
        WHERE NOT EXISTS (SELECT 1 FROM [Gold].[Dim_Affiliate_Payments] t
                           WHERE t.bk_Payout_ID = s.Payout_ID);
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
