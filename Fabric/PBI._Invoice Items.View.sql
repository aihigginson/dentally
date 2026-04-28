/****** Object:  View [PBI].[_Invoice Items]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Invoice Items]
GO
CREATE   VIEW [PBI].[_Invoice Items] AS
SELECT [pk_Invoice_Item] AS [pk Invoice Item], [bk_Invoice_Item_ID] AS [bk Invoice Item ID], [fk_Patient] AS [fk Patient], [fk_Practitioner] AS [fk Practitioner], [fk_Payment_Plan] AS [fk Payment Plan], [fk_Treatment_Plan] AS [fk Treatment Plan], [fk_Account] AS [fk Account], [fk_Practice_Site] AS [fk Practice Site], [fk_User] AS [fk User], [fk_Date_Invoice] AS [fk Date Invoice], [fk_Date_Due] AS [fk Date Due], [fk_Date_Paid] AS [fk Date Paid], [fk_Date_Created] AS [fk Date Created], [Invoice_ID] AS [Invoice ID], [Treatment_Plan_Item_ID] AS [Treatment Plan Item ID], [Sundry_ID] AS [Sundry ID], [Item_Name] AS [Item Name], [Invoice_Reference] AS [Invoice Reference], [Invoice_Payment_Terms] AS [Invoice Payment Terms], [Invoice_Footnote] AS [Invoice Footnote], [Invoice_Paid] AS [Invoice Paid], [Item_Price] AS [Item Price], [Quantity] AS [Quantity], [Total_Price] AS [Total Price], [NHS_Charge] AS [NHS Charge], [Invoice_Amount] AS [Invoice Amount], [Invoice_Amount_Outstanding] AS [Invoice Amount Outstanding], [Invoice_NHS_Amount] AS [Invoice NHS Amount], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Invoice_Items];
GO
