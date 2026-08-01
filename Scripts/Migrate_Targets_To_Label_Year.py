"""
Migrate_Targets_To_Label_Year.py
Shift Input.Targets.FY from the old START-year convention to the new END/LABEL-year convention by
adding 1 to every target row for a tenant (e.g. tenant 100: FY 2025->2026, 2026->2027). Part of the
tenant-financial-year cutover -- run EXACTLY ONCE per environment, alongside the warehouse cutover
(the backend now interprets Input.Targets.FY as the label/end year). NHS targets/UDA are unaffected.

Idempotency: run-once by design. Defaults to a DRY RUN (shows before/after, changes nothing). Pass
--confirm to apply. It refuses to run twice via a marker row in Input.Migration_Applied.

Usage:
  python Scripts/Migrate_Targets_To_Label_Year.py --env dev  --tenant 100            # dry run
  python Scripts/Migrate_Targets_To_Label_Year.py --env dev  --tenant 100 --confirm  # apply
  python Scripts/Migrate_Targets_To_Label_Year.py --env prod --tenant 100 --confirm  # at go-live
"""
import argparse, struct, subprocess, sys, pyodbc

# AppDB server per env (the FY / targets source of truth). Prod filled in at go-live.
APPDB = {
    "dev":  ("emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.database.fabric.microsoft.com",
             "AppDB-4c31e989-45ca-456c-a319-1a7a262c8aa3"),
    # "prod": ("<prod-appdb-server>.database.fabric.microsoft.com", "<prod-appdb-name>"),
}
MIGRATION_KEY = "targets_fy_to_label_year_v1"


def _conn(server, db):
    tok = subprocess.check_output(
        ["az", "account", "get-access-token", "--resource",
         "https://database.windows.net", "--query", "accessToken", "-o", "tsv"], shell=True).decode().strip()
    tb = tok.encode("utf-16-le"); ts = struct.pack(f"<I{len(tb)}s", len(tb), tb)
    cs = (f"Driver={{ODBC Driver 18 for SQL Server}};Server={server},1433;Database={db};"
          f"Encrypt=yes;TrustServerCertificate=no;")
    c = pyodbc.connect(cs, attrs_before={1256: ts}); c.autocommit = True
    return c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--env", required=True, choices=list(APPDB))
    ap.add_argument("--tenant", type=int, required=True)
    ap.add_argument("--confirm", action="store_true", help="apply (default is a dry run)")
    a = ap.parse_args()
    server, db = APPDB[a.env]
    c = _conn(server, db); cur = c.cursor()

    # marker table (idempotency)
    cur.execute("""IF OBJECT_ID('Input.Migration_Applied') IS NULL
        CREATE TABLE Input.Migration_Applied (
            Migration_Key VARCHAR(100) NOT NULL, Tenant_ID INT NOT NULL,
            Applied_At DATETIME2(3) NOT NULL CONSTRAINT DF_Migr_Applied DEFAULT SYSUTCDATETIME(),
            CONSTRAINT PK_Input_Migration_Applied PRIMARY KEY (Migration_Key, Tenant_ID));""")
    cur.execute("SELECT Applied_At FROM Input.Migration_Applied WHERE Migration_Key=? AND Tenant_ID=?",
                MIGRATION_KEY, a.tenant)
    done = cur.fetchone()

    def dist():
        cur.execute("SELECT FY, COUNT(*) FROM Input.Targets WHERE Tenant_ID=? GROUP BY FY ORDER BY FY", a.tenant)
        return cur.fetchall()

    print(f"[{a.env}] tenant {a.tenant} -- BEFORE:", [tuple(r) for r in dist()])
    if done:
        print(f"ALREADY APPLIED at {done[0]} -- refusing to run again."); c.close(); return
    if not a.confirm:
        print("DRY RUN (no changes). Re-run with --confirm to apply (FY += 1)."); c.close(); return

    # NHS metrics (nhs%) stay on the Apr-Mar year -- only practice metrics move to the label year.
    cur.execute("UPDATE Input.Targets SET FY = FY + 1 WHERE Tenant_ID = ? AND Metric NOT LIKE 'nhs%'", a.tenant)
    n = cur.rowcount
    cur.execute("INSERT INTO Input.Migration_Applied (Migration_Key, Tenant_ID) VALUES (?, ?)", MIGRATION_KEY, a.tenant)
    print(f"APPLIED: {n} target rows shifted FY += 1.  AFTER:", [tuple(r) for r in dist()])
    c.close()


if __name__ == "__main__":
    main()
