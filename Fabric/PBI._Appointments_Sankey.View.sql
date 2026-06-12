/****** Object:  View [PBI].[_Appointments Sankey]    Script Date: 31/05/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP VIEW IF EXISTS [PBI].[_Appointments Sankey]
GO
CREATE VIEW [PBI].[_Appointments Sankey] AS

SELECT
    [Tenant_ID]                                        AS [Tenant ID],
    [fk_Date_Start]                                    AS [fk_Date_Start],
    [fk_Practice_Site]                                 AS [fk_Practice_Site],
    [fk_Practitioner]                                  AS [fk_Practitioner],
    CONCAT(N'Booking: ',  [Booking])                   AS [Source],
    CONCAT(N'Reason: ',   [Appointment_Reason])        AS [Destination],
    COUNT(*)                                           AS [Weight]
FROM Gold.Fact_Appointments
WHERE [Booking]            IS NOT NULL
  AND [Appointment_Reason] IS NOT NULL
GROUP BY [Tenant_ID], [fk_Date_Start], [fk_Practice_Site], [fk_Practitioner], [Booking], [Appointment_Reason]

UNION ALL

SELECT
    [Tenant_ID],
    [fk_Date_Start],
    [fk_Practice_Site],
    [fk_Practitioner],
    CONCAT(N'Reason: ',   [Appointment_Reason]),
    CONCAT(N'Delay: ',    [Delay]),
    COUNT(*)
FROM Gold.Fact_Appointments
WHERE [Appointment_Reason] IS NOT NULL
  AND [Delay]              IS NOT NULL
GROUP BY [Tenant_ID], [fk_Date_Start], [fk_Practice_Site], [fk_Practitioner], [Appointment_Reason], [Delay]

UNION ALL

SELECT
    [Tenant_ID],
    [fk_Date_Start],
    [fk_Practice_Site],
    [fk_Practitioner],
    CONCAT(N'Delay: ',    [Delay]),
    CONCAT(N'Next: ',     [Next_Appointment]),
    COUNT(*)
FROM Gold.Fact_Appointments
WHERE [Delay]             IS NOT NULL
  AND [Next_Appointment]  IS NOT NULL
GROUP BY [Tenant_ID], [fk_Date_Start], [fk_Practice_Site], [fk_Practitioner], [Delay], [Next_Appointment]

UNION ALL

SELECT
    [Tenant_ID],
    [fk_Date_Start],
    [fk_Practice_Site],
    [fk_Practitioner],
    CONCAT(N'Next: ',     [Next_Appointment]),
    CONCAT(N'State: ',    [Current_State]),
    COUNT(*)
FROM Gold.Fact_Appointments
WHERE [Next_Appointment]  IS NOT NULL
  AND [Current_State]     IS NOT NULL
GROUP BY [Tenant_ID], [fk_Date_Start], [fk_Practice_Site], [fk_Practitioner], [Next_Appointment], [Current_State];
GO
