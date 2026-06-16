/****** Object:  Table [Gold].[Fact_Appointment_Journey] ******/
-- Appointment-grain journey base table. One row per appointment, carrying the
-- static attributes (Booking, Appointment_Reason) + the look-ahead as FOUR
-- next-appointment POINTERS (the next non-cancelled/non-DNA appointment for the
-- same patient, per mode). The pointers store the TARGET's bk_Appointment_ID
-- (scoped by Tenant_ID). Gold.vw_Fact_Appointment_Journey resolves these into the
-- per-mode Delay / Next Appointment / Current State columns for the Alluvial.
--
-- Why pointers + full rebuild (not a delta): a cancellation shifts the "next"
-- pointer of EARLIER appointments, so a forward delta would miss them; a full
-- rebuild is simpler and always correct. Pointers (4 ints) are compact vs
-- materialising every mode's attributes here.
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
DROP TABLE IF EXISTS [Gold].[Fact_Appointment_Journey]
GO
CREATE TABLE [Gold].[Fact_Appointment_Journey](
    [pk_Appointment_Journey]      [bigint] IDENTITY NOT NULL,
    [Tenant_ID]                   [int]          NOT NULL,
    [bk_Appointment_ID]           [int]          NOT NULL,
    [fk_Patient]                  [bigint]       NULL,
    [fk_Practitioner]             [bigint]       NULL,
    [fk_Practice_Site]            [bigint]       NULL,
    [fk_Date_Start]               [bigint]       NULL,
    [Start_Time]                  [datetime2](3) NULL,
    [Booking]                     [varchar](50)  NULL,
    [Appointment_Reason]          [varchar](50)  NULL,
    [Is_Cancelled]                [bit]          NULL,
    [Is_DNA]                      [bit]          NULL,
    [Is_Completed]                [bit]          NULL,
    -- Look-ahead pointers: bk_Appointment_ID of the next non-cancelled/non-DNA
    -- appointment for this patient (Start_Time strictly later), per mode.
    [fk_Appointment_Next]         [int]          NULL,   -- next of ANY reason
    [fk_Appointment_Exam]         [int]          NULL,   -- next where Reason = 'Exam'
    [fk_Appointment_Hygiene]      [int]          NULL,   -- next where Reason = 'Hygiene'
    [fk_Appointment_Not_Hygiene]  [int]          NULL,   -- next where Reason <> 'Hygiene'
    [DW_Created_At]               [datetime2](6) NOT NULL,
    [DW_Updated_At]               [datetime2](6) NOT NULL
)
GO
