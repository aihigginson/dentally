# =====================================================================
# Reset_Dentally_Data.ps1 -- clean-slate the Dentally DATA layers for a from-the-top rebuild.
# =====================================================================
# TRUNCATEs every base table in Bronze / Silver / Gold (facts, dims, aggregates AND
# Gold.Load_Watermark -- the watermark reset is the easy-to-forget bit that otherwise makes the
# watermark facts reload 0 rows). PRESERVES everything else: Audit (Tenants / Process_Config /
# Environment_Config / run logs), Config (Metric_Definitions), Input (Targets), Security
# (Application_Users / Clients / RLS), Meta, Migrate (Deploy_Log), Test, dbo. So the tenant
# registration, RLS mapping, targets and ETL config survive -- only the data goes.
#
# All-tenant (DEV holds T100 only, T11/T12 empty). Stage (lakehouse stage_*) is NOT touched here --
# a full ingest overwrites it per tenant (replaceWhere). Uses the SP token from fabric_creds.local.ps1.
#
# SAFE BY DEFAULT: with no -Confirm it DRY-RUNS (lists tables + row counts, truncates nothing).
# Run for real:   .\Scripts\Reset_Dentally_Data.ps1 -Confirm
# Preview only:   .\Scripts\Reset_Dentally_Data.ps1
# =====================================================================
param(
    [switch]  $Confirm,
    [string]  $Database = 'WH_Dentally',
    [string[]]$Schemas  = @('Bronze', 'Silver', 'Gold')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'fabric_creds.local.ps1')

$Server = if ($env:FABRIC_SERVER) { $env:FABRIC_SERVER } else {
    'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com'
}
$body = @{ grant_type='client_credentials'; client_id=$env:FABRIC_SP_CLIENT_ID; client_secret=$env:FABRIC_SP_CLIENT_SECRET; scope='https://database.windows.net/.default' }
$tok  = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Uri "https://login.microsoftonline.com/$($env:FABRIC_SP_TENANT)/oauth2/v2.0/token" -Body $body).access_token

$c = New-Object System.Data.SqlClient.SqlConnection
$c.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
$c.AccessToken = $tok; $c.Open()
Write-Host "Connected to $Database on $Server" -ForegroundColor Cyan
Write-Host ("Target schemas: {0}" -f ($Schemas -join ', ')) -ForegroundColor Cyan

# Discover base tables in the target schemas.
$schemaList = ($Schemas | ForEach-Object { "'$_'" }) -join ','
$lc = $c.CreateCommand()
$lc.CommandText = "SELECT SCHEMA_NAME(schema_id)+'.'+name FROM sys.tables WHERE SCHEMA_NAME(schema_id) IN ($schemaList) ORDER BY 1"
$r = $lc.ExecuteReader(); $tables = @(); while ($r.Read()) { $tables += $r.GetValue(0) }; $r.Close()
Write-Host ("Found {0} data tables." -f $tables.Count) -ForegroundColor Cyan

if (-not $Confirm) {
    Write-Host "`nDRY RUN (no -Confirm) -- current row counts, nothing will be truncated:" -ForegroundColor Yellow
    $total = 0
    foreach ($t in $tables) {
        $vc = $c.CreateCommand(); $vc.CommandText = "SELECT COUNT_BIG(*) FROM $t"; $vc.CommandTimeout = 180
        $n = [int64]$vc.ExecuteScalar(); $total += $n
        if ($n -gt 0) { Write-Host ("  {0,-45} {1,12:N0} rows" -f $t, $n) }
    }
    Write-Host ("`nTotal rows across {0} tables: {1:N0}" -f $tables.Count, $total) -ForegroundColor Yellow
    Write-Host "Re-run with -Confirm to TRUNCATE all of the above (config/Audit/Security/Input preserved)." -ForegroundColor Yellow
    $c.Close(); return
}

Write-Host "`n-Confirm set -- TRUNCATING $($tables.Count) tables:" -ForegroundColor Red
$fail = 0
foreach ($t in $tables) {
    $tc = $c.CreateCommand(); $tc.CommandText = "TRUNCATE TABLE $t"; $tc.CommandTimeout = 300
    try   { [void]$tc.ExecuteNonQuery(); Write-Host "  OK   $t" -ForegroundColor Green }
    catch { $fail++;                     Write-Host "  FAIL $t  -- $($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host "`nVerify (should all be 0):" -ForegroundColor Cyan
foreach ($chk in @('Bronze.Practitioner_Diary', 'Silver.Practitioner_Diary', 'Gold.Fact_Practitioner_Diaries', 'Gold.Dim_Patients', 'Gold.Fact_Invoices', 'Gold.Load_Watermark')) {
    try { $vc = $c.CreateCommand(); $vc.CommandText = "SELECT COUNT_BIG(*) FROM $chk"; Write-Host ("  {0,-38} {1} rows" -f $chk, $vc.ExecuteScalar()) }
    catch { Write-Host ("  {0,-38} (not found / skipped)" -f $chk) -ForegroundColor DarkGray }
}
$c.Close()
if ($fail -gt 0) { Write-Host "`n$fail table(s) failed to truncate -- review above." -ForegroundColor Red }
else { Write-Host "`nData layers cleared. Config/Audit/Security/Input preserved. Ready for a full ingest + build." -ForegroundColor Green }
