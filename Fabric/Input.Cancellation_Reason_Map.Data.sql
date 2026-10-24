-- Input.Cancellation_Reason_Map -- tenant 100 (Maple Dental)
--
-- ==> AN UNMAPPED REASON READS AS ITSELF. <== Gold.Dim_Cancellation_Reasons falls back to the
-- raw text when no map row matches, so Standard_Cancellation_Reason has been echoing Maple's
-- own wording verbatim and nothing looked broken. The map was empty for EVERY tenant. Same
-- trap as Silver.Appointment_Reason_Map before V230, which read as 29.5% mapped while
-- appearing fine.
--
-- WHY IT MATTERS NOW: the lapsing-patient flow needs "cancelled by the practice" separated
-- from "cancelled by the patient". Maple's reasons carry that in a prefix, so the split is
-- derivable -- but only once the raw strings are mapped onto the standard list.
--
-- "No reason recorded" rolls into Other, as agreed. It is 10,774 of 32,773 cancellations --
-- a third of them -- so Other is not a rounding bucket here and should be shown, not hidden.
--
-- Full refresh. Add a tenant by adding its rows; an unmapped reason still falls through as
-- its own text, which is exactly the failure this file exists to stop.

DELETE FROM [Input].[Cancellation_Reason_Map];
GO

INSERT INTO [Input].[Cancellation_Reason_Map]
    (Tenant_ID, Source_Cancellation_Reason, Standard_Cancellation_Reason, DW_Created_At, DW_Updated_At)
SELECT v.Tenant_ID, v.Source_Cancellation_Reason, v.Standard_Cancellation_Reason,
       SYSUTCDATETIME(), SYSUTCDATETIME()
FROM (VALUES
    -- Practice initiated -- the practice cancelled on the patient. 5,269 appointments.
    (100, 'Practice - Clinician unavailable', 'Practice Initiated'),
    (100, 'Practice - Closed',                'Practice Initiated'),
    (100, 'Practice - Staff Training',        'Practice Initiated'),

    -- Patient initiated. 'Patient - Cancelled' is 13,757 on its own and carries no reason
    -- beyond the fact that the patient cancelled, so it lands on Personal as the catch-all
    -- rather than being invented into a finer one.
    (100, 'Patient - Cancelled',              'Patient - Personal'),
    (100, 'Patient -',                        'Patient - Personal'),
    (100, 'Patient - Family Emergency',       'Patient - Personal'),
    (100, 'Patient - Holiday',                'Patient - Personal'),
    (100, 'Patient - Childcare issues',       'Patient - Personal'),
    (100, 'Patient - Car trouble',            'Patient - Personal'),
    (100, 'Patient - Illness',                'Patient - Unwell'),
    (100, 'Patient - self isolating',         'Patient - Unwell'),
    (100, 'Patient - Work Issue',             'Patient - Work'),
    (100, 'Patient - Financial reasons',      'Patient - Financial'),

    -- 'Was Not Brought' is a child who did not arrive -- a DNA in substance, whatever the
    -- appointment was marked as.
    (100, 'Patient - Was Not Brought',        'Did Not Attend'),

    -- ==> SHORT NOTICE IS AN URGENCY, NOT A WHO. <== Mapping it to Short Notice keeps the
    -- standard list intact but loses the patient attribution for 565 cancellations. Flagged
    -- deliberately: if the flow should count these as patient-initiated, change this one row
    -- to 'Patient - Personal' and Short Notice stops being reachable for this tenant.
    (100, 'Patient - Short Notice',           'Short Notice'),

    -- A third of all cancellations. Attributable to nobody, and shown as such.
    (100, 'No reason recorded',               'Other')
) AS v (Tenant_ID, Source_Cancellation_Reason, Standard_Cancellation_Reason);
GO
