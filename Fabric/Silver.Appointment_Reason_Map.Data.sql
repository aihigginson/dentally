/****** Object:  Data [Silver].[Appointment_Reason_Map]    Script Date: 13/05/2026 ******/
-- Seed rows for appointment reason → category mapping.
-- Populate with real reason text values once data from multiple customers is available.
-- All reasons not in this table will default to 'Other' in the journey attribute derivation.
-- Category values: Exam, Hygiene, Continuing Treatment, Emergency, Review, Other
-- Sort_Key drives ordering in PBI visuals (1=Exam, 2=Hygiene, 3=Continuing Treatment, 4=Emergency, 5=Review, 6=Other)

DELETE FROM [Silver].[Appointment_Reason_Map];
GO

INSERT INTO [Silver].[Appointment_Reason_Map] ([Reason_Text], [Category], [Sort_Key]) VALUES
-- ── Exam ─────────────────────────────────────────────────────────────────────
    ('Examination',               'Exam', 1),
    ('Routine Examination',       'Exam', 1),
    ('New Patient Examination',   'Exam', 1),
-- ── Hygiene ──────────────────────────────────────────────────────────────────
    ('Hygiene',                   'Hygiene', 2),
    ('Hygiene Appointment',       'Hygiene', 2),
    ('Scale and Polish',          'Hygiene', 2),
    ('Exam and Scale and Polish', 'Hygiene', 2),
-- ── Continuing Treatment ─────────────────────────────────────────────────────
    ('Treatment',                 'Continuing Treatment', 3),
    ('Filling',                   'Continuing Treatment', 3),
    ('Extraction',                'Continuing Treatment', 3),
    ('Root Canal Treatment',      'Continuing Treatment', 3),
    ('Crown Preparation',         'Continuing Treatment', 3),
    ('Crown Fit',                 'Continuing Treatment', 3),
-- ── Emergency ────────────────────────────────────────────────────────────────
    ('Emergency',                 'Emergency', 4),
    ('Emergency - Pain',          'Emergency', 4),
-- ── Review ───────────────────────────────────────────────────────────────────
    ('Review',                    'Review', 5),
    ('Post-Op Review',            'Review', 5),
    ('Denture Review',            'Review', 5),
    ('Implant Consultation',      'Review', 5),
    ('Whitening Consultation',    'Review', 5);
GO
