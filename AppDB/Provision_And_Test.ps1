# Provision_And_Test.ps1  --  Phase 0 spike harness for the target-model Fabric SQL Database.
# ASCII only (PS 5.1 reads without BOM as CP1252).
#
# What it does:
#   1. Connects to the Fabric SQL DB endpoint (Entra token, same SP as the warehouse tooling).
#   2. Runs AppDB_Input_Schema.sql (idempotent -- creates schema + 3 Input tables).
#   3. CRUD smoke test on a throwaway tenant (999): insert -> select -> delete.
#
# PREREQ (user, in the Fabric portal -- see README.md):
#   - the Fabric SQL Database exists in the dev workspace
#   - the deploy SP has been granted access in it (CREATE USER ... FROM EXTERNAL PROVIDER; db_owner)
#   - you have its Server (FQDN) + Database name
#
# Run:  .\AppDB\Provision_And_Test.ps1 -Server '<fqdn>' -Database '<dbname>'
#   or set $env:APPDB_SERVER / $env:APPDB_DB and run with no args.

param(
    [string]$Server   = $env:APPDB_SERVER,
    [string]$Database  = $env:APPDB_DB,
    [switch]$SchemaOnly
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path (Split-Path -Parent $here) 'Scripts\fabric_creds.local.ps1')

if ([string]::IsNullOrWhiteSpace($Server) -or [string]::IsNullOrWhiteSpace($Database)) {
    throw "Provide -Server and -Database (or set APPDB_SERVER / APPDB_DB). Get these from the Fabric SQL DB 'Connection strings' panel."
}

Write-Host "Target: $Database @ $Server" -ForegroundColor Cyan

# --- token (SP client-credentials, Azure SQL scope) ---
$body = @{
    grant_type    = 'client_credentials'
    client_id     = $env:FABRIC_SP_CLIENT_ID
    client_secret = $env:FABRIC_SP_CLIENT_SECRET
    scope         = 'https://database.windows.net/.default'
}
$tok = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' `
        -Uri "https://login.microsoftonline.com/$($env:FABRIC_SP_TENANT)/oauth2/v2.0/token" -Body $body).access_token

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
$conn.AccessToken = $tok
try {
    $conn.Open()
    Write-Host "Connected OK" -ForegroundColor Green
} catch {
    Write-Host "CONNECT FAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "If this is a login error, the SP is not yet a user in the DB -- run the grant in README.md step 3." -ForegroundColor Yellow
    throw
}

function Exec($sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 120
    return $cmd.ExecuteNonQuery()
}
function Scalar($sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = 120
    return $cmd.ExecuteScalar()
}

# --- 1. schema (split on GO; SqlClient does not parse GO) ---
Write-Host "`n[1] Applying schema..." -ForegroundColor Cyan
$schemaPath = Join-Path $here 'AppDB_Input_Schema.sql'
$raw = Get-Content -Raw -Path $schemaPath
$batches = [regex]::Split($raw, '(?im)^\s*GO\s*$')
foreach ($b in $batches) { if ($b.Trim().Length -gt 0) { [void](Exec $b) } }
Write-Host "    schema applied (3 Input tables present)" -ForegroundColor Green

if ($SchemaOnly) { $conn.Close(); Write-Host "`nSchema-only run done." -ForegroundColor Green; return }

# --- 2. CRUD smoke test (throwaway tenant 999) ---
Write-Host "`n[2] CRUD smoke test (Tenant_ID=999)..." -ForegroundColor Cyan
[void](Exec "DELETE FROM Input.Practitioner_Role WHERE Tenant_ID=999; DELETE FROM Input.Targets WHERE Tenant_ID=999; DELETE FROM Input.Metric_Variance WHERE Tenant_ID=999;")
[void](Exec @"
INSERT INTO Input.Practitioner_Role (Tenant_ID, Practitioner_ID, Custom_Role, Updated_By) VALUES
 (999, 1, 'Dentist', 'spike'), (999, 2, 'Specialist Implantologist', 'spike');
INSERT INTO Input.Targets (Tenant_ID, FY, Metric, Target_Level, Target_Value, Updated_By) VALUES
 (999, 2026, 'exam_ratio', 'Practice', 55.0, 'spike'),
 (999, 2026, 'exam_ratio', 'Specialist Implantologist', 12.0, 'spike');
INSERT INTO Input.Metric_Variance (Tenant_ID, Metric, Variance, Updated_By) VALUES (999, 'exam_ratio', 5.0, 'spike');
"@)
$r = Scalar "SELECT COUNT(*) FROM Input.Practitioner_Role WHERE Tenant_ID=999"
$t = Scalar "SELECT COUNT(*) FROM Input.Targets WHERE Tenant_ID=999"
$v = Scalar "SELECT COUNT(*) FROM Input.Metric_Variance WHERE Tenant_ID=999"
Write-Host ("    inserted+read: roles=$r targets=$t variance=$v") -ForegroundColor Green
[void](Exec "DELETE FROM Input.Practitioner_Role WHERE Tenant_ID=999; DELETE FROM Input.Targets WHERE Tenant_ID=999; DELETE FROM Input.Metric_Variance WHERE Tenant_ID=999;")
Write-Host "    cleaned up test rows" -ForegroundColor Green

$conn.Close()
if ($r -eq 2 -and $t -eq 2 -and $v -eq 1) {
    Write-Host "`nSPIKE PASS: connect + schema + CRUD all good. Pipe (app -> SQL DB) proven." -ForegroundColor Green
} else {
    Write-Host "`nSPIKE FAIL: unexpected row counts." -ForegroundColor Red
}
