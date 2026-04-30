# =============================================================================
# Stage_Ingest
# =============================================================================
# Pulls data from the Dentally API and writes it to LH_Dentally as Delta tables.
# Attach LH_Dentally to this notebook before running.
#
# Parameters:
#   tenant_id     - Integer identifier for this dental practice (1 for dev)
#   api_base_url  - Base URL of the Dentally API (mock or real)
#   api_key       - Bearer token for API authentication
#   full_refresh  - True = pull everything; False = pull changes since last run
#   updated_after - ISO8601 datetime for incremental start point.
#                   Leave blank to default to the last 24 hours.
# =============================================================================


# -----------------------------------------------------------------------------
# CELL 1 - Parameters
# Tag this cell as a Parameters cell in Fabric (... menu -> Toggle parameter cell)
# -----------------------------------------------------------------------------

tenant_id     = 1
api_base_url  = "https://dentally-production.up.railway.app"
api_key       = "dev-mock-key-abc123"
full_refresh  = True
updated_after = ""   # e.g. "2024-01-01T00:00:00" — leave blank to use last 24h

# When called from Orchestrate_Bronze, parameters arrive as Python native types.
# Guard against string values in case of environment differences.
if isinstance(full_refresh, str):
    full_refresh = full_refresh.strip().lower() == "true"
if isinstance(tenant_id, str):
    tenant_id = int(tenant_id)


# -----------------------------------------------------------------------------
# CELL 2 - Imports
# -----------------------------------------------------------------------------

import json
import requests
from datetime import datetime, timezone, timedelta
from pyspark.sql import functions as F
from pyspark.sql.types import StringType, StructType, StructField


# -----------------------------------------------------------------------------
# CELL 3 - Setup
# -----------------------------------------------------------------------------

http_headers = {"Authorization": f"Bearer {api_key}"}

# Default incremental window: last 24 hours
if not updated_after and not full_refresh:
    updated_after = (
        datetime.now(timezone.utc) - timedelta(hours=24)
    ).strftime("%Y-%m-%dT%H:%M:%S")

load_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
incremental_params = {} if full_refresh else {"updated_after": updated_after}

print(f"Tenant ID    : {tenant_id}")
print(f"API base URL : {api_base_url}")
print(f"Mode         : {'Full refresh' if full_refresh else f'Incremental from {updated_after}'}")
print(f"Load time    : {load_timestamp}")


# -----------------------------------------------------------------------------
# CELL 4 - Helper functions
# -----------------------------------------------------------------------------

def fetch_all(endpoint, extra_params=None):
    """Fetch every page from an API endpoint and return all records as a list."""
    params = {**(extra_params or {}), "per_page": 100}
    records = []
    page = 1

    while True:
        response = requests.get(
            f"{api_base_url}{endpoint}",
            headers=http_headers,
            params={**params, "page": page}
        )
        response.raise_for_status()
        data = response.json()

        entity_key = next(k for k in data if k != "meta")
        records.extend(data[entity_key])

        if page >= data["meta"]["total_pages"]:
            break
        page += 1

    return records


def fetch_one(endpoint):
    """Fetch a single (non-paginated) resource and return the object."""
    response = requests.get(f"{api_base_url}{endpoint}", headers=http_headers)
    response.raise_for_status()
    data = response.json()
    entity_key = next(k for k in data)
    return data[entity_key]


def write_stage(records, table_name):
    """Add metadata columns and write records to a Lakehouse Delta table.
    All values stored as strings — Stage is raw landing, Bronze does the typing."""
    if not records:
        print(f"  {table_name}: 0 records (skipped)")
        return

    for r in records:
        r["tenant_id"]          = tenant_id
        r["DW_Stage_Loaded_At"] = load_timestamp

    all_keys = set()
    for r in records:
        all_keys.update(r.keys())
    schema = StructType([StructField(k, StringType(), True) for k in sorted(all_keys)])

    def _to_str(v):
        if v is None:
            return None
        elif isinstance(v, (dict, list)):
            return json.dumps(v)
        else:
            return str(v)

    str_records = [{k: _to_str(v) for k, v in r.items()} for r in records]
    df = spark.createDataFrame(str_records, schema=schema)
    df.write.format("delta").mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"stage_{table_name}")
    print(f"  {table_name}: {len(records)} records -> stage_{table_name}")


# -----------------------------------------------------------------------------
# CELL 5 - Reference data (always full refresh — no updated_after)
# -----------------------------------------------------------------------------

print("Reference data...")
write_stage([fetch_one("/v1/practice")],                    "practice")
write_stage(fetch_all("/v1/sites"),                         "sites")
write_stage(fetch_all("/v1/users"),                         "users")
write_stage(fetch_all("/v1/practitioners"),                 "practitioners")
write_stage(fetch_all("/v1/payment_plans"),                 "payment_plans")
write_stage(fetch_all("/v1/treatments"),                    "treatments")
write_stage(fetch_all("/v1/treatment_categories"),          "treatment_categories")
write_stage(fetch_all("/v1/acquisition_sources"),           "acquisition_sources")
write_stage(fetch_all("/v1/sundries"),                      "sundries")
write_stage(fetch_all("/v1/contracts"),                     "contracts")
write_stage(fetch_all("/v1/fees"),                          "fees")
write_stage(fetch_all("/v1/practitioner_diary_breaks"),     "practitioner_diary_breaks")


# -----------------------------------------------------------------------------
# CELL 6 - Transactional data (incremental or full refresh)
# -----------------------------------------------------------------------------

print("Transactional data...")
write_stage(fetch_all("/v1/patients",                    incremental_params), "patients")
write_stage(fetch_all("/v1/accounts"),                                        "accounts")
write_stage(fetch_all("/v1/appointments",               incremental_params), "appointments")
write_stage(fetch_all("/v1/invoices",                   incremental_params), "invoices")
write_stage(fetch_all("/v1/invoice_items",              incremental_params), "invoice_items")
write_stage(fetch_all("/v1/payments",                   incremental_params), "payments")
write_stage(fetch_all("/v1/treatment_plans",            incremental_params), "treatment_plans")
write_stage(fetch_all("/v1/treatment_plan_items",       incremental_params), "treatment_plan_items")
write_stage(fetch_all("/v1/recalls",                    incremental_params), "recalls")
write_stage(fetch_all("/v1/practitioner_diary_entries", incremental_params), "practitioner_diary_entries")
write_stage(fetch_all("/v1/nhs_claims",                 incremental_params), "nhs_claims")
write_stage(fetch_all("/v1/patient_stats",              incremental_params), "patient_stats")
write_stage(fetch_all("/v1/payment_allocations",        incremental_params), "payment_allocations")
write_stage(fetch_all("/v1/payment_explanations",       incremental_params), "payment_explanations")
write_stage(fetch_all("/v1/treatment_appointments",     incremental_params), "treatment_appointments")


# -----------------------------------------------------------------------------
# CELL 7 - Done
# -----------------------------------------------------------------------------

print("\nStage load complete.")
