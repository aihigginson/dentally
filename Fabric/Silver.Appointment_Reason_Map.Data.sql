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
    ('Examination',                        'Exam', 1),
    ('Examination Extensive',              'Exam', 1),
    ('Full Case Assessment',               'Exam', 1),
    ('Routine Examination',                'Exam', 1),
    ('New Patient Examination',            'Exam', 1),
    ('Recall Examination',                 'Exam', 1),
-- HEX is the live practice's own shorthand for a check-up and was the single largest gap
-- in this map: 15,796 completed appointments across 3,016 patients matching nothing, so
-- their check-ups registered as no category at all and the ownership rule in
-- Gold.usp_Load_Dim_Patients could not see them.
-- ==> 42% OF HEX APPOINTMENTS ARE TAKEN BY A HYGIENIST. <== That is harmless for ownership,
-- which filters on User_Role = 'Dentist' and drops that half, but it DOES move the
-- Exam/Hygiene split in Gold.Fact_Appointment_Journey -- hence the reload in V229.
-- 'Hex 20' and 'Hex 30' are NOT exams despite the name -- they are 96% hygienist-performed
-- (1,500 of 1,571 and 1,242 of 1,268), so they are timed hygiene slots. They are mapped in
-- the Hygiene block below; mapping them here would misclassify 2,742 hygiene appointments.
    ('HEX',                                'Exam', 1),
-- ==> SELF-NAMED REASONS. ZERO DOWNSTREAM CHANGE, AND THE WHOLE POINT. <== The loader
-- resolves Appointment_Reason as COALESCE(map.Category, raw text), so these two already
-- produced exactly these strings by falling through unmapped -- which is precisely why the
-- map looked like it was working when it was matching nothing. 31,741 and 20,793
-- appointments at the live practice. Anything that JOINS the map (the ownership rule in
-- Gold.usp_Load_Dim_Patients) could not see them at all until now.
    ('Exam',                               'Exam', 1),
    ('Continuing Treatment',                'Continuing Treatment', 3),
-- The practice's own shorthand for a pre-operative assessment, with the proviso that the
-- op may turn out not to be needed. 2,508 completed appointments, Principal-heavy, on a
-- 316-day recurrence, and never charged -- it was the largest single item in the no-payer
-- bucket (1,178 of 1,193 completed, none invoiced).
    ('View',                               'Continuing Treatment', 3),
-- ── Hygiene ──────────────────────────────────────────────────────────────────
    ('Hygiene',                            'Hygiene', 2),
    ('Hygiene Appointment',                'Hygiene', 2),
    ('Scale & Polish',                     'Hygiene', 2),
    ('Scale and Polish',                   'Hygiene', 2),
    ('Exam and Scale and Polish',          'Hygiene', 2),
    ('Oral Hygiene Instruction',           'Hygiene', 2),
    ('Fluoride Varnish',                   'Hygiene', 2),
-- The practice's own hygiene slot names. 'Hex 20' and 'Hex 30' sit here rather than with
-- HEX above: they are 96% hygienist-performed (1,500 of 1,571 and 1,242 of 1,268), so they
-- are timed hygiene appointments, not the dentist check-up HEX denotes. All of these
-- currently leak raw practice shorthand into a product column.
    ('20 Scale & Polish',                  'Hygiene', 2),
    ('30 Scale & Polish',                  'Hygiene', 2),
    ('Routine Hygiene',                    'Hygiene', 2),
    ('Hex 20',                             'Hygiene', 2),
    ('Hex 30',                             'Hygiene', 2),
    ('3 12 Hyg',                           'Hygiene', 2),
-- ── Continuing Treatment ─────────────────────────────────────────────────────
    ('Treatment',                          'Continuing Treatment', 3),
    ('Fissure Sealant',                    'Continuing Treatment', 3),
    ('Periodontal Treatment (Visit 1)',    'Continuing Treatment', 3),
    ('Periodontal Treatment (Visit 2)',    'Continuing Treatment', 3),
    ('Root Surface Debridement',           'Continuing Treatment', 3),
    ('Filling',                            'Continuing Treatment', 3),
    ('Amalgam Filling',                    'Continuing Treatment', 3),
    ('Composite Filling (1 surface)',      'Continuing Treatment', 3),
    ('Composite Filling (2 surface)',      'Continuing Treatment', 3),
    ('Composite Filling (3+ surfaces)',    'Continuing Treatment', 3),
    ('Inlay / Onlay',                      'Continuing Treatment', 3),
    ('Veneer',                             'Continuing Treatment', 3),
    ('Extraction',                         'Continuing Treatment', 3),
    ('Extraction (Simple)',                'Continuing Treatment', 3),
    ('Extraction (Surgical)',              'Continuing Treatment', 3),
    ('Root Canal Treatment',               'Continuing Treatment', 3),
    ('Root Canal (Anterior)',              'Continuing Treatment', 3),
    ('Root Canal (Premolar)',              'Continuing Treatment', 3),
    ('Root Canal (Molar)',                 'Continuing Treatment', 3),
    ('Crown Preparation',                  'Continuing Treatment', 3),
    ('Crown Fit',                          'Continuing Treatment', 3),
    ('Crown (Porcelain Fused Metal)',      'Continuing Treatment', 3),
    ('Crown (Full Ceramic)',               'Continuing Treatment', 3),
    ('Bridge (per unit)',                  'Continuing Treatment', 3),
    ('Partial Denture',                    'Continuing Treatment', 3),
    ('Full Denture',                       'Continuing Treatment', 3),
    ('Implant Placement',                  'Continuing Treatment', 3),
    ('Implant Crown',                      'Continuing Treatment', 3),
    ('X-Ray Bitewing',                     'Continuing Treatment', 3),
    ('X-Ray Periapical',                   'Continuing Treatment', 3),
    ('Panoramic (OPG)',                    'Continuing Treatment', 3),
    ('Ortho Records',                      'Continuing Treatment', 3),
    ('Fixed Appliance Fitting',            'Continuing Treatment', 3),
    ('Adjustment',                         'Continuing Treatment', 3),
    ('Debond',                             'Continuing Treatment', 3),
    ('Retainer Fitting',                   'Continuing Treatment', 3),
    ('Aligner Treatment',                  'Continuing Treatment', 3),
-- ── Emergency ────────────────────────────────────────────────────────────────
    ('Emergency',                          'Emergency', 4),
    ('Emergency - Pain',                   'Emergency', 4),
    ('Emergency Examination',              'Emergency', 4),
    ('Emergency Treatment',                'Emergency', 4),
-- ── Review ───────────────────────────────────────────────────────────────────
    ('Review',                             'Review', 5),
    ('Post-Op Review',                     'Review', 5),
    ('Denture Review',                     'Review', 5),
    ('Implant Consultation',               'Review', 5),
    ('Whitening Consultation',             'Review', 5),
    ('Whitening (Home Kit)',               'Review', 5),
    ('Whitening (In-Chair)',               'Review', 5),
    ('Composite Bonding',                  'Review', 5),
    ('Ortho Consultation',                 'Review', 5),
    ('Retention Review',                   'Review', 5),
    ('Treatment Consultation',             'Review', 5),
    ('Smile Consultation',                 'Review', 5);
GO
