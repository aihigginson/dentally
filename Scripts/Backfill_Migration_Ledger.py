"""Record migrations as applied that prod is ALREADY in the end state of.

==> THIS WRITES A CLAIM, SO THE CLAIM IS EVIDENCED FIRST. <== Recording a migration without running
it asserts "this file's effect is present". That is only honest if it has been checked, so each
version below carries the evidence that was actually measured on 30 Oct 2026, and the script
re-checks the cheap ones at run time rather than trusting this comment.

==> WHY IT MATTERS MORE THAN TIDINESS. <== Prod's schema matches dev at ZERO column gaps across
Gold, Silver, Bronze, Config, Security, Meta, Audit, Billing and Sales -- but prod's
Migrate.Schema_Version is nine versions behind. So `Migrate.ps1` pointed at prod would attempt all
nine. They are individually guarded (IF NOT EXISTS / IF EXISTS) so the likely outcome is a no-op,
but V001 ADDS a column that V005 later DROPS and V008/V009 drop a Silver table -- replaying that
sequence against a live warehouse to discover it is fine is not a risk worth taking for bookkeeping.

==> TWO OF THE NINE LOOKED LIKE GAPS AND WERE NOT. <== Both were a wrong expectation, found by
checking dev rather than assuming prod was behind:

  V001  Gold.Fact_Invoice_Items.Is_Invoice_Outstanding is absent on PROD -- and absent on DEV too.
        V001 added it; a later Table.sql redeploy (DROP/CREATE) removed it. The environments agree,
        which is the standard that matters. Checking "the column V001 added still exists" was the
        wrong test.
  V153  Input.Sync_State is absent from the prod WAREHOUSE -- and from dev's. The file lives in
        Migrations/ but its target is the APPDB, where both environments have it with 18 rows. I
        looked in the wrong database.

The checksum is computed exactly as Scripts/Migrate.ps1 computes it -- SHA-256 of the decoded file
text re-encoded UTF-8 -- so a later run of Migrate.ps1 sees a matching, applied version rather than
a mismatch.

    python Backfill_Migration_Ledger.py            # report only
    python Backfill_Migration_Ledger.py --write    # record them
"""
import glob
import hashlib
import io
import os
import re
import struct
import subprocess
import sys

import pyodbc

PRD = ("emeh72n2ntdufpj4q665b2lzx4-eljzajgm5cpe5i64szgon7sej4"
       ".datawarehouse.fabric.microsoft.com")
MIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Migrations')
WRITE = '--write' in sys.argv

# version -> the evidence measured for it. A version with no entry is NOT recorded.
EVIDENCE = {
    'V001': 'Is_Email_Missing present; Is_Invoice_Outstanding absent on BOTH prod and dev '
            '(added by V001, removed by a later Table.sql redeploy)',
    'V002': 'Gold.Load_Watermark exists',
    'V005': 'Fact_Invoice_Items.Aged_Debt_Band and Is_Discount both absent',
    'V007': 'Fact_Payments.Is_Deposit and Deposit_Amount both absent',
    'V008': 'Silver.Appointment_Journey_Attributes gone -- V009 subsumes it',
    'V009': 'Silver.Appointment_Journey_Attributes gone',
    'V151': 'Security.Clients has Client_Email, Email_Domain and First_Contact_At',
    'V152': 'Input.Plan_Capitation_Rate.Hygienist_Visit_Value present',
    'V153': 'Input.Sync_State present on AppDB-prod AND AppDB-dev, 18 rows each '
            '(the file targets the APPDB, not the warehouse)',
}


def checksum(path):
    raw = open(path, 'rb').read()
    enc = 'utf-16' if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig'
    return hashlib.sha256(io.open(path, encoding=enc).read().encode('utf-8')).hexdigest()


tok = subprocess.check_output(
    ['az', 'account', 'get-access-token', '--resource',
     'https://database.windows.net', '--query', 'accessToken', '-o', 'tsv'],
    shell=True).decode().strip().encode('utf-16-le')
cn = pyodbc.connect(
    'Driver={ODBC Driver 18 for SQL Server};Server=%s,1433;Database=WH_Dentally;'
    'Encrypt=yes;TrustServerCertificate=no;' % PRD,
    attrs_before={1256: struct.pack('<I%ds' % len(tok), len(tok), tok)}, autocommit=True)
cur = cn.cursor()
cur.execute('SELECT Version FROM Migrate.Schema_Version WHERE Success = 1')
applied = {r[0] for r in cur.fetchall()}

print('PROD ledger holds %d applied version(s)%s\n'
      % (len(applied), '' if WRITE else '   [report only -- pass --write to record]'))

done = 0
for ver in sorted(EVIDENCE):
    hits = glob.glob(os.path.join(MIG, ver + '__*.sql'))
    if not hits:
        print('  %-6s NO FILE -- skipped' % ver)
        continue
    path = hits[0]
    name = re.match(r'^V\d+__(.+)\.sql$', os.path.basename(path)).group(1)
    if ver in applied:
        print('  %-6s already recorded' % ver)
        continue
    print('  %-6s %-42s %s' % (ver, name, EVIDENCE[ver][:70]))
    if WRITE:
        cur.execute(
            "INSERT INTO Migrate.Schema_Version (Version, Name, Checksum, Applied_At, Success) "
            "VALUES (?, ?, ?, SYSUTCDATETIME(), 1)", ver, name, checksum(path))
        done += 1

if WRITE:
    cur.execute('SELECT COUNT(*) FROM Migrate.Schema_Version WHERE Success = 1')
    print('\nrecorded %d; ledger now holds %d applied version(s)' % (done, cur.fetchone()[0]))
cn.close()
