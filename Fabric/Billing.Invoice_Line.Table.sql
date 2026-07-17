-- Billing.Invoice_Line
-- One line per (Tenant, User, billed month): the profile the user held x that month's effective price.
-- Generated on the 1st of the following month by Billing.usp_Generate_Invoice_Lines (idempotent per
-- month -- it clears and regenerates the month). IDEMPOTENT CREATE so invoice history survives redeploys.
IF OBJECT_ID('Billing.Invoice_Line') IS NULL
CREATE TABLE [Billing].[Invoice_Line] (
    [Tenant_ID]    [int]          NOT NULL,
    [Year_Month]   [int]          NOT NULL,    -- billed month, YYYYMM
    [User_UPN]     [varchar](255) NOT NULL,
    [Display_Name] [varchar](255) NULL,
    [Profile_Key]  [varchar](50)  NOT NULL,
    [Value]        [decimal](9,2) NOT NULL,
    [Generated_At] [datetime2](3) NOT NULL
);
GO
