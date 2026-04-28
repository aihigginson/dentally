/****** Object:  View [PBI].[_Appointments]    Script Date: 20/04/2026 10:15:06 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Appointments]
GO
CREATE   VIEW [PBI].[_Appointments] AS
SELECT [pk_Appointment] AS [pk Appointment], [bk_Appointment_ID] AS [bk Appointment ID], [fk_Patient] AS [fk Patient], [fk_Practitioner] AS [fk Practitioner], [fk_Payment_Plan] AS [fk Payment Plan], [fk_Practice_Site] AS [fk Practice Site], [fk_User] AS [fk User], [fk_Date_Start] AS [fk Date Start], [fk_Date_Pending] AS [fk Date Pending], [fk_Date_Created] AS [fk Date Created], [Room_ID] AS [Room ID], [State] AS [State], [Reason] AS [Reason], [Treatment_Description] AS [Treatment Description], [Notes] AS [Notes], [Cancellation_Reason_ID] AS [Cancellation Reason ID], [Arrived_At] AS [Arrived At], [In_Surgery_At] AS [In Surgery At], [Completed_At] AS [Completed At], [Confirmed_At] AS [Confirmed At], [Cancelled_At] AS [Cancelled At], [Did_Not_Attend_At] AS [Did Not Attend At], [Start_Time] AS [Start Time], [Finish_Time] AS [Finish Time], [Pending_At] AS [Pending At], [Is_Completed] AS [Is Completed], [Is_Cancelled] AS [Is Cancelled], [Is_DNA] AS [Is DNA], [Is_Arrived] AS [Is Arrived], [Duration_Mins] AS [Duration Mins], [Waiting_Mins] AS [Waiting Mins], [In_Surgery_Mins] AS [In Surgery Mins], [DW_Created_At] AS [DW Created At], [DW_Updated_At] AS [DW Updated At]
FROM Gold.[Fact_Appointments];
GO
