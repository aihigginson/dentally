# =============================================================================
# Orchestrate_Bronze
# =============================================================================
# Loops through all active tenants in Audit.Tenants and for each one:
#   1. Runs Stage_Ingest  — pulls from the Dentally API into LH_Dentally
#   2. Runs Bronze.usp_Load_All — upserts Stage data into WH_Dentally Bronze tables
#
# After this notebook completes, run Silver/Gold procedures to process all
# tenants downstream (those layers read Bronze directly and are not per-tenant).
#
# Parameters:
#   warehouse_sql_endpoint - Fabric Warehouse SQL endpoint
#                            (find in Fabric portal: Warehouse → Settings → SQL connection string)
#                            Format: <workspace-id>.datawarehouse.fabric.microsoft.com
#   warehouse_name         - Name of the Fabric Warehouse (default: WH_Dentally)
# =============================================================================


# -----------------------------------------------------------------------------
# CELL 1 - Parameters
# Tag this cell as a Parameters cell in Fabric (... menu -> Toggle parameter cell)
# -----------------------------------------------------------------------------

warehouse_sql_endpoint = ""    # e.g. abc123.datawarehouse.fabric.microsoft.com
warehouse_name         = "WH_Dentally"


# -----------------------------------------------------------------------------
# CELL 2 - Imports
# -----------------------------------------------------------------------------

import pyodbc
import struct
import time
from datetime import datetime, timezone


# -----------------------------------------------------------------------------
# CELL 3 - Connect to Warehouse
# -----------------------------------------------------------------------------

if not warehouse_sql_endpoint:
    raise ValueError("warehouse_sql_endpoint parameter is required")

# Acquire token using Fabric's built-in mssparkutils credential provider
token        = mssparkutils.credentials.getToken("https://database.windows.net/")
token_bytes  = token.encode("UTF-16-LE")
token_struct = struct.pack(f'<I{len(token_bytes)}s', len(token_bytes), token_bytes)

conn_str = (
    "Driver={ODBC Driver 18 for SQL Server};"
    f"Server={warehouse_sql_endpoint},1433;"
    f"Database={warehouse_name};"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
)

conn   = pyodbc.connect(conn_str, attrs_before={1256: token_struct})
conn.autocommit = True
cursor = conn.cursor()

print(f"Connected to {warehouse_name} @ {warehouse_sql_endpoint}")


# -----------------------------------------------------------------------------
# CELL 4 - Read active tenants
# -----------------------------------------------------------------------------

cursor.execute("""
    SELECT Tenant_ID, Tenant_Name, API_Base_URL, API_Key,
           Full_Refresh, Last_Loaded_At
    FROM   Audit.Tenants
    WHERE  Is_Active = 1
    ORDER  BY Tenant_ID
""")
tenants = cursor.fetchall()

if not tenants:
    raise RuntimeError("No active tenants found in Audit.Tenants — nothing to do")

print(f"Found {len(tenants)} active tenant(s)\n")


# -----------------------------------------------------------------------------
# CELL 5 - Process each tenant: Stage → Bronze
# -----------------------------------------------------------------------------

results = []

for row in tenants:
    tenant_id, tenant_name, api_base_url, api_key, full_refresh_flag, last_loaded_at = row

    full_refresh   = bool(full_refresh_flag)
    updated_after  = "" if full_refresh or not last_loaded_at else str(last_loaded_at)

    print("=" * 60)
    print(f"Tenant {tenant_id}: {tenant_name}")
    print(f"  Mode         : {'Full refresh' if full_refresh else 'Incremental'}")
    if not full_refresh:
        print(f"  Updated after: {updated_after or 'last 24h (no prior run recorded)'}")
    print("=" * 60)

    # ── Stage ingest ──────────────────────────────────────────────────────────
    print("  [1/2] Stage_Ingest ...")
    mssparkutils.notebook.run(
        "Stage_Ingest",
        600,
        {
            "tenant_id"    : tenant_id,
            "api_base_url" : api_base_url,
            "api_key"      : api_key,
            "full_refresh" : full_refresh,
            "updated_after": updated_after,
        }
    )

    # ── Bronze load ───────────────────────────────────────────────────────────
    # Brief pause to allow Fabric's lakehouse metadata to propagate to the
    # Warehouse SQL engine before querying Stage views.
    time.sleep(30)
    print("  [2/2] Bronze.usp_Load_All ...")
    cursor.execute(
        "EXEC Bronze.usp_Load_All @Tenant_ID = ?, @Full_Refresh = ?",
        tenant_id, int(full_refresh)
    )

    # ── Mark run complete ─────────────────────────────────────────────────────
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    cursor.execute(
        "UPDATE Audit.Tenants SET Last_Loaded_At = ?, Full_Refresh = 0 WHERE Tenant_ID = ?",
        now, tenant_id
    )

    results.append((tenant_id, tenant_name, full_refresh))
    print(f"  Done — Last_Loaded_At set to {now}\n")


# -----------------------------------------------------------------------------
# CELL 6 - Summary
# -----------------------------------------------------------------------------

print("=" * 60)
print("Orchestration complete")
print("=" * 60)
for tenant_id, tenant_name, full_refresh in results:
    mode = "full refresh" if full_refresh else "incremental"
    print(f"  Tenant {tenant_id} ({tenant_name}): {mode}")

print()
print("Next step: run Silver and Gold procedures to propagate changes downstream.")
