# ---------------------------------------------------------------------------
# Check_RLS_Isolation.ps1  --  behavioral RLS isolation test (via XMLA / ADOMD)
# ---------------------------------------------------------------------------
# The complement to Check_RLS_Coverage.ps1. Coverage proves every tenant-bearing
# table HAS an RLS filter; this proves the filter WORKS: querying the model as a
# specific user (EffectiveUserName) must expose no tenant outside that user's
# allowed set (+ the -1 sentinel). Requires the test SP to be a workspace ADMIN
# (EffectiveUserName impersonation needs admin) and the model to contain >1
# tenant's data for the test to be meaningful.
#
# Creds: Scripts/fabric_creds.local.ps1 (gitignored) or FABRIC_SP_* env vars.
#   RLS_TEST_UPN (default admin@analytically.info) -- the user to impersonate.
#   PBI_WORKSPACE_NAME / PBI_DATASET_NAME / RLS_ROLE_NAME / RLS_TENANT_COLUMN as Coverage.
#
# Exit: 0 = isolated correctly; 1 = leak (a user saw another tenant); 2 = config/conn error.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET
$WsName   = if ($env:PBI_WORKSPACE_NAME) { $env:PBI_WORKSPACE_NAME } else { 'DEV - DM Dentally' }
$DsName   = if ($env:PBI_DATASET_NAME)   { $env:PBI_DATASET_NAME }   else { 'PBI Dentally' }
$RlsRole  = if ($env:RLS_ROLE_NAME)      { $env:RLS_ROLE_NAME }      else { 'RLS' }
$TenantCol= if ($env:RLS_TENANT_COLUMN)  { $env:RLS_TENANT_COLUMN }  else { 'Tenant ID' }
$Upn      = if ($env:RLS_TEST_UPN)       { $env:RLS_TEST_UPN }       else { 'admin@analytically.info' }

if (-not ($Tenant -and $ClientId -and $Secret)) { Write-Host "Missing FABRIC_SP_* creds." -ForegroundColor Red; exit 2 }

$adomd = $env:ADOMD_DLL
if (-not $adomd -or -not (Test-Path $adomd)) { $adomd = "$env:ProgramFiles\Microsoft.NET\ADOMD.NET\170\Microsoft.AnalysisServices.AdomdClient.dll" }
if (-not (Test-Path $adomd)) {
    $adomd = (Get-ChildItem "$env:ProgramFiles\Microsoft.NET\ADOMD.NET" -Recurse -Filter 'Microsoft.AnalysisServices.AdomdClient.dll' -ErrorAction SilentlyContinue |
              Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName)
}
if (-not $adomd -or -not (Test-Path $adomd)) { Write-Host "ADOMD.NET client not found (set ADOMD_DLL)." -ForegroundColor Red; exit 2 }
Add-Type -Path $adomd

$base = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$WsName;Initial Catalog=$DsName;User ID=app:$ClientId@$Tenant;Password=$Secret;"

function Run-Dax([string]$dax, [string]$extra) {
    $conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection($base + $extra)
    $conn.Open()
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $dax
    $rdr = $cmd.ExecuteReader()
    $names = @(); for ($i = 0; $i -lt $rdr.FieldCount; $i++) { $n = $rdr.GetName($i); if ($n -match '\[([^\]]+)\]') { $n = $Matches[1] }; $names += $n }
    $rows = @()
    while ($rdr.Read()) { $o = [ordered]@{}; for ($i = 0; $i -lt $rdr.FieldCount; $i++) { $o[$names[$i]] = $rdr.GetValue($i) }; $rows += [pscustomobject]$o }
    $rdr.Close(); $conn.Close()
    ,$rows
}

# 1. Enumerate tenant-bearing tables (name) from the model metadata.
try {
    $tablesRows = Run-Dax 'EVALUATE INFO.TABLES()' ''
    $colsRows   = Run-Dax 'EVALUATE INFO.COLUMNS()' ''
} catch { Write-Host "Metadata query failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
$tableName = @{}; foreach ($r in $tablesRows) { $tableName[[string]$r.ID] = [string]$r.Name }
$tenantTables = @()
foreach ($c in $colsRows) {
    $cn = if ($c.ExplicitName) { [string]$c.ExplicitName } elseif ($c.InferredName) { [string]$c.InferredName } else { '' }
    if ($cn -eq $TenantCol) { $tenantTables += $tableName[[string]$c.TableID] }
}
$tenantTables = @($tenantTables | Sort-Object -Unique)

# 2. Allowed tenants for the test UPN (read with no role).
$safeUpn = $Upn.Replace('"','""')
$allowedRows = Run-Dax "EVALUATE SELECTCOLUMNS(FILTER('Application Users','Application Users'[User UPN]=""$safeUpn""),""t"",'Application Users'[Tenant ID])" ''
$allowed = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($r in $allowedRows) { [void]$allowed.Add([string]$r.t) }
[void]$allowed.Add('-1')   # the sentinel is always permitted by the filter
if ($allowed.Count -le 1) { Write-Host "User '$Upn' maps to no tenant in 'Application Users' -- cannot test." -ForegroundColor Red; exit 2 }

Write-Host "Impersonating : $Upn"
Write-Host "Allowed tenants (+sentinel): $(@($allowed) -join ',')"
Write-Host "Tenant-bearing tables to probe: $($tenantTables.Count)`n"

# 3. For each table, query VALUES([Tenant ID]) AS the user; flag anything outside allowed.
$imp = "Roles=$RlsRole;EffectiveUserName=$Upn;"
$leaks = @()
foreach ($t in $tenantTables) {
    try { $rows = Run-Dax "EVALUATE VALUES('$t'[$TenantCol])" $imp }
    catch { Write-Host ("  {0,-42} QUERY ERROR: {1}" -f $t, $_.Exception.Message) -ForegroundColor Yellow; continue }
    $seen = @($rows | ForEach-Object { [string]$_.($TenantCol) })
    $bad  = @($seen | Where-Object { -not $allowed.Contains($_) })
    if ($bad.Count -gt 0) { $leaks += [pscustomobject]@{ Table = $t; Leaked = ($bad -join ',') } }
    Write-Host ("  {0,-42} sees: {1}" -f $t, (($seen | Sort-Object) -join ','))
}

Write-Host ""
if ($leaks.Count -gt 0) {
    Write-Host "LEAK -- '$Upn' can see other tenants' data:" -ForegroundColor Red
    $leaks | ForEach-Object { Write-Host ("  - {0}: tenant(s) {1}" -f $_.Table, $_.Leaked) -ForegroundColor Red }
    exit 1
}
Write-Host "OK -- '$Upn' sees only their allowed tenant(s) across all $($tenantTables.Count) tenant-bearing tables." -ForegroundColor Green
exit 0
