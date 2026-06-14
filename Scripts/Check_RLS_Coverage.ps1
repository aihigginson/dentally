# ---------------------------------------------------------------------------
# Check_RLS_Coverage.ps1  --  model-level RLS leak guard (via XMLA / ADOMD.NET)
# ---------------------------------------------------------------------------
# Connects to the published Power BI semantic model over the XMLA endpoint as
# the service principal and verifies that the 'RLS' role applies a per-table
# filter to EVERY tenant-bearing table (any table with a 'Tenant ID' column).
# A tenant-bearing table with no RLS filter is a silent cross-tenant leak.
#
# Uses ADOMD.NET (installed by SSMS / Power BI Desktop) -- no executeQueries
# REST gating, just the workspace Member role + org-wide XMLA endpoint.
#
# Creds come from Scripts/fabric_creds.local.ps1 (gitignored) or env vars:
#   FABRIC_SP_TENANT, FABRIC_SP_CLIENT_ID, FABRIC_SP_CLIENT_SECRET
# Model location (defaults to the shared dev dataset):
#   PBI_WORKSPACE_NAME (default 'DEV - DM Dentally'), PBI_DATASET_NAME (default 'PBI Dentally')
#   RLS_ROLE_NAME (default 'RLS'), RLS_TENANT_COLUMN (default 'Tenant ID')
#
# Exit: 0 = every tenant-bearing table filtered; 1 = leak(s); 2 = config/conn error.
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

if (-not ($Tenant -and $ClientId -and $Secret)) {
    Write-Host "Missing FABRIC_SP_TENANT / FABRIC_SP_CLIENT_ID / FABRIC_SP_CLIENT_SECRET." -ForegroundColor Red
    exit 2
}

# Load ADOMD.NET (prefer the standalone install, fall back to a search).
$adomd = "$env:ProgramFiles\Microsoft.NET\ADOMD.NET\170\Microsoft.AnalysisServices.AdomdClient.dll"
if (-not (Test-Path $adomd)) {
    $adomd = (Get-ChildItem "$env:ProgramFiles\Microsoft.NET\ADOMD.NET" -Recurse -Filter 'Microsoft.AnalysisServices.AdomdClient.dll' -ErrorAction SilentlyContinue |
              Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName)
}
if (-not $adomd -or -not (Test-Path $adomd)) { Write-Host "ADOMD.NET client not found." -ForegroundColor Red; exit 2 }
Add-Type -Path $adomd

$dataSource = "powerbi://api.powerbi.com/v1.0/myorg/$WsName"
$connStr = "Provider=MSOLAP;Data Source=$dataSource;Initial Catalog=$DsName;User ID=app:$ClientId@$Tenant;Password=$Secret;"

$conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection($connStr)
try { $conn.Open() } catch { Write-Host "XMLA connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
Write-Host "Connected to '$DsName' in '$WsName' via XMLA." -ForegroundColor Green

function Norm([string]$k) { if ($k -match '\[([^\]]+)\]\s*$') { return $Matches[1] } else { return $k } }

function Invoke-Dax([string]$dax) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $dax
    $rdr = $cmd.ExecuteReader()
    $names = @(); for ($i = 0; $i -lt $rdr.FieldCount; $i++) { $names += (Norm $rdr.GetName($i)) }
    $rows = @()
    while ($rdr.Read()) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $rdr.FieldCount; $i++) { $o[$names[$i]] = $rdr.GetValue($i) }
        $rows += [pscustomobject]$o
    }
    $rdr.Close()
    ,$rows
}

# NOTE: assign each result to a variable then iterate with foreach -- piping
# Invoke-Dax output directly into ForEach-Object mis-enumerates the row set.
try {
    $tablesRows = Invoke-Dax 'EVALUATE INFO.TABLES()'
    $rolesRows  = Invoke-Dax 'EVALUATE INFO.ROLES()'
    $colsRows   = Invoke-Dax 'EVALUATE INFO.COLUMNS()'
    $permRows   = Invoke-Dax 'EVALUATE INFO.TABLEPERMISSIONS()'
} catch { Write-Host "Metadata query failed: $($_.Exception.Message)" -ForegroundColor Red; $conn.Close(); exit 2 }

$tables = @{}
foreach ($r in $tablesRows) { $tables[[string]$r.ID] = [string]$r.Name }

$roleId = $null
foreach ($r in $rolesRows) { if ([string]$r.Name -eq $RlsRole) { $roleId = [string]$r.ID } }
if (-not $roleId) {
    Write-Host "No role named '$RlsRole'. Roles present: $(($rolesRows | ForEach-Object { $_.Name }) -join ', ')" -ForegroundColor Red
    $conn.Close(); exit 2
}

$filtered = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($p in $permRows) {
    if ([string]$p.RoleID -eq $roleId -and "$($p.FilterExpression)".Trim().Length -gt 0) { [void]$filtered.Add([string]$p.TableID) }
}

$tenantTableIds = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($c in $colsRows) {
    $cn = if ($c.ExplicitName) { [string]$c.ExplicitName } elseif ($c.InferredName) { [string]$c.InferredName } else { '' }
    if ($cn -eq $TenantCol) { [void]$tenantTableIds.Add([string]$c.TableID) }
}

$leaks = @(); $covered = @()
foreach ($t in $tenantTableIds) { if ($filtered.Contains($t)) { $covered += $tables[$t] } else { $leaks += $tables[$t] } }
$leaks   = @($leaks   | Sort-Object)
$covered = @($covered | Sort-Object)

$conn.Close()

Write-Host ""
Write-Host "RLS role             : $RlsRole"
Write-Host "Tenant column        : $TenantCol"
Write-Host "Tenant-bearing tables: $($tenantTableIds.Count)"
Write-Host "  filtered by RLS    : $($covered.Count)"
Write-Host "  NOT filtered (LEAK): $($leaks.Count)"
Write-Host ""
if ($leaks.Count -gt 0) {
    Write-Host "LEAK -- tenant-bearing tables with NO RLS filter:" -ForegroundColor Red
    $leaks | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "OK -- every tenant-bearing table is filtered by the '$RlsRole' role." -ForegroundColor Green
$covered | ForEach-Object { Write-Host "  [filtered] $_" }
exit 0
