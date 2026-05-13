import csv

channel_to_appt = {
    ('New',           'Exam (Current)'): 320,
    ('BBYL',          'Exam (Current)'): 960,
    ('BBYL',          'Treatment (Current)'): 240,
    ('Online Booking','Exam (Current)'): 160,
    ('Online Booking','Treatment (Current)'): 40,
    ('Emergency',     'Exam (Current)'): 40,
    ('Emergency',     'Treatment (Current)'): 80,
    ('Referral',      'Exam (Current)'): 80,
    ('Referral',      'Treatment (Current)'): 20,
    ('Other',         'Exam (Current)'): 40,
    ('Other',         'Treatment (Current)'): 20,
}

appt_to_outcome = {
    'Exam (Current)': {
        'BBYL Exam':      900 / 1600,
        'BBYL Treatment': 300 / 1600,
        'Awaiting Recall':200 / 1600,
        'Recall Sent':    120 / 1600,
        'Closed':          80 / 1600,
    },
    'Treatment (Current)': {
        'BBYL Exam':      160 / 400,
        'BBYL Treatment': 240 / 400,
    },
}

outcome_to_next_appt = {
    'BBYL Exam':      'Exam (Next)',
    'BBYL Treatment': 'Treatment (Next)',
    'Awaiting Recall':'Exam (Next)',
    'Recall Sent':    'Exam (Next)',
    'Closed':         'None',
}

next_appt_to_state = {
    'Exam (Next)': {
        'Exam Scheduled':      1200 / 1380,
        'Uncertain':            100 / 1380,
        'Requiring Contact':     60 / 1380,
        'No longer a Patient':   20 / 1380,
    },
    'Treatment (Next)': {
        'Treatment Scheduled': 470 / 540,
        'Uncertain':            40 / 540,
        'Requiring Contact':    20 / 540,
        'No longer a Patient':  10 / 540,
    },
    'None': {
        'No longer a Patient': 1.0,
    },
}

rows = []
for (channel, appt), ch_count in channel_to_appt.items():
    for outcome, outcome_prop in appt_to_outcome[appt].items():
        next_appt = outcome_to_next_appt[outcome]
        outcome_count = ch_count * outcome_prop
        for state, state_prop in next_appt_to_state[next_appt].items():
            count = round(outcome_count * state_prop)
            if count > 0:
                rows.append([channel, appt, outcome, next_appt, state, count])

out_path = r'C:\Users\aihig\OneDrive\Dentally\Code\PBI\Sankey_Patient_Flow_Wide.csv'
with open(out_path, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['Channel', 'Current Appointment', 'Next Outcome', 'Next Appointment', 'Current State', 'Patient Count'])
    w.writerows(rows)

total = sum(r[5] for r in rows)
print(f"Rows: {len(rows)}, Total patients: {total}")

# Generate SQL data file for Gold.Fact_Patient_Journeys
value_lines = []
for i, (channel, current_appt, next_outcome, next_appt, current_state, count) in enumerate(rows, 1):
    value_lines.append(
        f"    ({i}, '{channel}', '{current_appt}', '{next_outcome}', '{next_appt}', '{current_state}', {count})"
    )

sql = '\n'.join([
    '-- =============================================================================',
    '-- Gold.Fact_Patient_Journeys — seed data',
    '-- =============================================================================',
    '-- Fake patient journey flow data for Sankey / Alluvial diagram prototype.',
    '-- 104 rows: unique path combinations across 5 stages.',
    '--   Channel > Current_Appointment > Next_Outcome > Next_Appointment > Current_State',
    '-- =============================================================================',
    '',
    'DELETE FROM Gold.Fact_Patient_Journeys;',
    'GO',
    '',
    'INSERT INTO Gold.Fact_Patient_Journeys',
    '    (pk_patient_journey, Channel, Current_Appointment, Next_Outcome,',
    '     Next_Appointment, Current_State, Patient_Count)',
    'VALUES',
    ',\n'.join(value_lines) + ';',
    'GO',
])

sql_path = r'C:\Users\aihig\OneDrive\Dentally\Code\Fabric\Gold.Fact_Patient_Journeys.Data.sql'
with open(sql_path, 'w', encoding='utf-8') as f:
    f.write(sql)

print(f"SQL data file written: {sql_path}")
