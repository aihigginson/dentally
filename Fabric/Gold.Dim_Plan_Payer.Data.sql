--------------------------------------------------------------------
--  Data   :  Gold.Dim_Plan_Payer
--  Author :  AIH
--  Purpose:  Seed the four payers. DELETE + INSERT: fixed reference data with hardcoded
--            keys, so a full replace is idempotent and the only way a rename reaches the
--            model. The keys are written into Gold.Fact_Treatment_Plans.fk_Plan_Payer and
--            bound by report filters -- add a payer by taking the next free number, never
--            renumber an existing one.
--
--            ==> PRECEDENCE IS WHAT WAS CHARGED, NOT WHAT THE PATIENT IS. <== Private wins
--            over everything: 2,663 plans belong to capitation members who were ALSO charged
--            privately, and 245 carry UDA value alongside a private charge. In both the
--            patient paid, so Private is the honest answer. NHS then beats plan membership
--            for the 111 plans holding both.
--
--  History:
--    *01     22/10/2026  AIH V231: initial release.
--------------------------------------------------------------------
DELETE FROM [Gold].[Dim_Plan_Payer];
GO

INSERT INTO [Gold].[Dim_Plan_Payer]
    ([pk_Plan_Payer], [Payer_Code], [Payer_Name], [Payer_Description],
     [Sort_Order], [Is_Charged], [Is_Clinical_Activity],
     [Plan_Payer_Count], [DW_Created_At], [DW_Updated_At])
SELECT v.[pk_Plan_Payer], v.[Payer_Code], v.[Payer_Name], v.[Payer_Description],
       v.[Sort_Order], v.[Is_Charged], v.[Is_Clinical_Activity],
       1, SYSUTCDATETIME(), SYSUTCDATETIME()
FROM (VALUES
    (-1, 'UNKNOWN', 'Unknown',
        'Placeholder so a plan mid-load still joins. A fk of -1 hides under All and blanks every tile under a selection, so the row has to exist.',
        0, 0, 0),
    (1, 'NHS', 'NHS',
        'Carries UDA value. The NHS paid for this course; the patient band charge is a slice of that value, never income on top of it.',
        1, 1, 1),
    (2, 'PLAN', 'Plan (Capitation)',
        'The patient is a member of a capitation plan priced in Input.Plan_Capitation_Rate. The monthly fee covered this course, so the plan carries no private value and that is correct rather than missing.',
        2, 1, 1),
    (3, 'PRIVATE', 'Private',
        'The patient was charged directly. Takes precedence over plan membership and over NHS value: if private value was invoiced then the patient paid, whatever else also applied to them.',
        3, 1, 1),
    (4, 'NO_PAYER', 'No Payer',
        'No private value, no UDA value, and the patient is not a plan member -- so nobody paid. Two populations sit here and they are not alike: genuine ex-gratia treatment (fillings and root planing redone for nothing after work that did not go perfectly) and plans whose only items are General Note, Notes, Prescription or Covid Screening Questions, which are filing rather than dentistry. Is_Clinical_Activity = 0 so the second kind cannot inflate activity counts.',
        4, 0, 0)
) AS v ([pk_Plan_Payer], [Payer_Code], [Payer_Name], [Payer_Description],
        [Sort_Order], [Is_Charged], [Is_Clinical_Activity]);
GO

-- Exactly one payer may be excluded from clinical activity. Widening that silently removes
-- real dentistry from every activity figure in the product.
DECLARE @n INT, @e VARCHAR(4000);
SELECT @n = SUM(CASE WHEN [Is_Clinical_Activity] = 0 AND [pk_Plan_Payer] > 0 THEN 1 ELSE 0 END)
FROM   [Gold].[Dim_Plan_Payer];
IF @n <> 1
BEGIN
    SET @e = 'Dim_Plan_Payer seed FAILED: ' + CAST(@n AS VARCHAR(10))
           + ' payer(s) excluded from clinical activity, expected exactly 1.';
    THROW 50620, @e, 1;
END;
GO
