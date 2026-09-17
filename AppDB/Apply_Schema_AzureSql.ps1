# Apply_Schema_AzureSql.ps1
# ---------------------------------------------------------------------------
# Applies AppDB_Input_Schema.sql to an AZURE SQL database (sql-analytically), and grants the
# app + deploy identities. Sibling to Provision_And_Test.ps1, which targets the Fabric SQL DB.
#
# Why a second script: Provision_And_Test.ps1 authenticates as the DEPLOY SP, which cannot
# connect to a brand-new Azure SQL server -- the server has Entra-ONLY auth and the SP has no
# user in the database yet. Bootstrapping therefore has to run as the Entra admin (a human),
# which is this script. After it has run once, the SP can connect and the normal tooling works.
#
# The schema file itself is UNCHANGED between the two: Fabric SQL Database is the Azure SQL
# engine, so the PKs, DEFAULTs and DATETIME2 all apply verbatim.
#
# Run (as the Entra admin, az login first):
#   .\AppDB\Apply_Schema_AzureSql.ps1 -Database 'AppDB-dev'
# ---------------------------------------------------------------------------
param(
    [string]$Server   = 'sql-analytically.database.windows.net',
    [Parameter(Mandatory = $true)][string]$Database,
    [string[]]$GrantReadWrite = @(),   # managed identities / SPs needing db_datareader+writer
    [string[]]$GrantOwner     = @()    # deploy identities needing db_owner
)
$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$schema = Join-Path $here 'AppDB_Input_Schema.sql'
if (-not (Test-Path $schema)) { throw "schema not found: $schema" }

$py = @'
import os, sys, struct, subprocess, pyodbc

server, database, schema_path = sys.argv[1], sys.argv[2], sys.argv[3]
grants_rw = [g for g in (sys.argv[4] or '').split(',') if g]
grants_ow = [g for g in (sys.argv[5] or '').split(',') if g]

out = subprocess.check_output(["az", "account", "get-access-token", "--resource",
                               "https://database.windows.net", "--query", "accessToken",
                               "-o", "tsv"], shell=True)
tb = out.decode().strip().encode("utf-16-le")
ts = struct.pack(f"<I{len(tb)}s", len(tb), tb)
cs = (f"Driver={{ODBC Driver 18 for SQL Server}};Server={server},1433;"
      f"Database={database};Encrypt=yes;TrustServerCertificate=no;Login Timeout=30;")
cn = pyodbc.connect(cs, attrs_before={1256: ts}, autocommit=True)
cur = cn.cursor()

# GO is a client batch separator, not T-SQL -- split on it and send each batch separately.
sql = open(schema_path, encoding="utf-8-sig").read()
batches = [b.strip() for b in
           __import__("re").split(r"(?im)^\s*GO\s*$", sql) if b.strip()]
for i, b in enumerate(batches, 1):
    cur.execute(b)
print(f"schema applied: {len(batches)} batches")

# Entra principals need a database user before they can connect. FROM EXTERNAL PROVIDER
# resolves the name in Entra; idempotent via the sys.database_principals guard.
for name, roles in [(g, ["db_datareader", "db_datawriter"]) for g in grants_rw] + \
                   [(g, ["db_owner"]) for g in grants_ow]:
    cur.execute(
        "IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = ?) "
        "EXEC('CREATE USER [' + ? + '] FROM EXTERNAL PROVIDER')", name, name)
    for r in roles:
        cur.execute("EXEC('ALTER ROLE " + r + " ADD MEMBER [' + ? + ']')", name)
    print(f"granted {name}: {', '.join(roles)}")

cur.execute("SELECT TABLE_SCHEMA + '.' + TABLE_NAME FROM INFORMATION_SCHEMA.TABLES "
            "WHERE TABLE_SCHEMA = 'Input' ORDER BY TABLE_NAME")
print("tables:", ", ".join(r[0] for r in cur.fetchall()))
cn.close()
'@

$tmp = Join-Path $env:TEMP 'apply_appdb_schema.py'
$py | Out-File -Encoding UTF8 $tmp
Write-Host "Applying $schema -> $Server / $Database"
python $tmp $Server $Database $schema ($GrantReadWrite -join ',') ($GrantOwner -join ',')
if ($LASTEXITCODE -ne 0) { throw "schema apply failed" }
Write-Host "done." -ForegroundColor Green
