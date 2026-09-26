# ---------------------------------------------------------------------------
# Check_RLS_Expression.ps1  --  does every RLS filter actually say what it should?
# ---------------------------------------------------------------------------
# The COMPLEMENT to Check_RLS_Coverage.ps1, which proves every tenant-bearing
# table HAS a filter but never reads what the filter SAYS -- it passes on any
# non-empty string. That is the right test for "did I miss a table" and no test
# at all for "did I apply the rule correctly", which is a different way to leak:
# a rule pasted into 40 tables and edited in 39 looks fully covered.
#
# Checks each table permission on the RLS role for the two halves the rule needs:
#
#   PERMISSION   the set-membership test (USERPRINCIPALNAME). Without it a table
#                is filtered by something, but not by who is asking.
#   SCOPE        the narrowing (CUSTOMDATA). Without it the report receives EVERY
#                tenant the caller may see and ADDS THEM UP -- which is silent,
#                and reads as a plausible number rather than an error.
#
# Reads metadata through TOM (Microsoft.AnalysisServices.Tabular), which ships
# with the SqlServer PowerShell module -- no ADOMD install needed.
#
# Creds: Scripts/fabric_creds.local.ps1 (gitignored) or FABRIC_SP_* env vars.
#   PBI_WORKSPACE_NAME (default 'DEV - DM Dentally')
#   PBI_DATASET_NAME   (default 'PBI Dentally')
#   RLS_ROLE_NAME      (default 'RLS')
#   RLS_TENANT_COLUMN  (default 'Tenant ID')
#
# Exit: 0 = every tenant-bearing table has both halves; 1 = at least one does
#       not; 2 = config/connection error.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$Tenant    = $env:FABRIC_SP_TENANT
$ClientId  = $env:FABRIC_SP_CLIENT_ID
$Secret    = $env:FABRIC_SP_CLIENT_SECRET
$WsName    = if ($env:PBI_WORKSPACE_NAME) { $env:PBI_WORKSPACE_NAME } else { 'DEV - DM Dentally' }
$DsName    = if ($env:PBI_DATASET_NAME)   { $env:PBI_DATASET_NAME }   else { 'PBI Dentally' }
$RlsRole   = if ($env:RLS_ROLE_NAME)      { $env:RLS_ROLE_NAME }      else { 'RLS' }
$TenantCol = if ($env:RLS_TENANT_COLUMN)  { $env:RLS_TENANT_COLUMN }  else { 'Tenant ID' }

if (-not ($Tenant -and $ClientId -and $Secret)) {
    Write-Host "Missing FABRIC_SP_TENANT / FABRIC_SP_CLIENT_ID / FABRIC_SP_CLIENT_SECRET." -ForegroundColor Red
    exit 2
}

# TOM, from the SqlServer module. Load Core first -- Tabular depends on it, and
# Add-Type will not resolve a sibling assembly on its own.
$modBase = (Get-Module -ListAvailable SqlServer | Sort-Object Version -Descending |
            Select-Object -First 1).ModuleBase
if (-not $modBase) { Write-Host "SqlServer PowerShell module not found." -ForegroundColor Red; exit 2 }
foreach ($dll in @('Microsoft.AnalysisServices.Core.dll', 'Microsoft.AnalysisServices.Tabular.dll')) {
    $path = Get-ChildItem $modBase -Recurse -Filter $dll -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { Write-Host "$dll not found under $modBase" -ForegroundColor Red; exit 2 }
    Add-Type -Path $path
}

$connStr = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$WsName;" +
           "Initial Catalog=$DsName;User ID=app:$ClientId@$Tenant;Password=$Secret;"

$srv = New-Object Microsoft.AnalysisServices.Tabular.Server
try { $srv.Connect($connStr) }
catch { Write-Host "XMLA connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

$db = $srv.Databases.GetByName($DsName)
if (-not $db) { Write-Host "Dataset '$DsName' not found in '$WsName'." -ForegroundColor Red; $srv.Disconnect(); exit 2 }
$model = $db.Model
Write-Host "Connected to '$DsName' in '$WsName'." -ForegroundColor Green

$role = $model.Roles | Where-Object { $_.Name -eq $RlsRole } | Select-Object -First 1
if (-not $role) {
    Write-Host "No role named '$RlsRole'. Roles: $(($model.Roles | ForEach-Object Name) -join ', ')" -ForegroundColor Red
    $srv.Disconnect(); exit 2
}

# Tenant-bearing tables are the ones that MUST carry the rule.
$tenantTables = @()
foreach ($t in $model.Tables) {
    if ($t.Columns | Where-Object { $_.Name -eq $TenantCol }) { $tenantTables += $t.Name }
}

$perm = @{}
foreach ($tp in $role.TablePermissions) { $perm[$tp.Name] = "$($tp.FilterExpression)" }

# ==> THE RULE'S OWN SOURCE TABLE IS EXEMPT FROM THE NARROWING. <== The rule reads the set of
# tenants a user may see out of a table, and filters that table to the caller's own rows.
# Narrowing THAT by CUSTOMDATA would be wrong twice over: the set-membership test on every
# other table needs it to expose the user's whole permitted set, and a table cut to one tenant
# cannot answer "may they see this one". Detected from the rule itself rather than hard-coded,
# so renaming the table does not silently turn the exemption off.
$sourceTables = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($e in $perm.Values) {
    foreach ($m in [regex]::Matches($e, "FILTER\(\s*'([^']+)'")) {
        [void]$sourceTables.Add($m.Groups[1].Value)
    }
}

$ok = @(); $noScope = @(); $noPerm = @(); $missing = @(); $exempt = @()
foreach ($name in ($tenantTables | Sort-Object)) {
    if ($sourceTables.Contains($name)) {
        if ($perm.ContainsKey($name) -and $perm[$name] -match '(?i)USERPRINCIPALNAME') { $exempt += $name }
        else { $noPerm += $name }
        continue
    }
    if (-not $perm.ContainsKey($name) -or $perm[$name].Trim().Length -eq 0) { $missing += $name; continue }
    $e = $perm[$name]
    $hasPerm  = $e -match '(?i)USERPRINCIPALNAME'
    $hasScope = $e -match '(?i)CUSTOMDATA'
    if     (-not $hasPerm)  { $noPerm  += $name }
    elseif (-not $hasScope) { $noScope += $name }
    else                    { $ok      += $name }
}

Write-Host ""
Write-Host "RLS role              : $RlsRole"
Write-Host "Tenant-bearing tables : $($tenantTables.Count)"
Write-Host "  both halves present : $($ok.Count)"
Write-Host "  no CUSTOMDATA       : $($noScope.Count)"
Write-Host "  no USERPRINCIPALNAME: $($noPerm.Count)"
Write-Host "  no filter at all    : $($missing.Count)"
Write-Host "  rule source (exempt): $($exempt.Count)   $($exempt -join ', ')"
Write-Host ""

# One sample, so a wrong-but-consistent rule is visible rather than merely counted.
if ($ok.Count -gt 0) {
    Write-Host "Sample expression ($($ok[0])):" -ForegroundColor Cyan
    Write-Host $perm[$ok[0]]
    Write-Host ""
}

# Are they all the SAME rule? Forty tables agreeing is the point; one differing
# is how a table quietly keeps the old behaviour after a bulk edit.
$distinct = @($tenantTables | Where-Object { $perm.ContainsKey($_) } |
              ForEach-Object { ($perm[$_] -replace '\s+', ' ').Trim() } |
              Sort-Object -Unique)
Write-Host "Distinct filter expressions across tenant-bearing tables: $($distinct.Count)"
if ($distinct.Count -gt 1) {
    Write-Host "  (expected 1 -- differing rules listed below)" -ForegroundColor Yellow
    $i = 0
    foreach ($d in $distinct) {
        $i++
        $users = @($tenantTables | Where-Object { $perm.ContainsKey($_) -and
                   (($perm[$_] -replace '\s+', ' ').Trim()) -eq $d })
        Write-Host ""
        Write-Host "  [$i] on $($users.Count) table(s): $($users -join ', ')" -ForegroundColor Yellow
        Write-Host "      $d"
    }
}

# A renamed-and-left-behind copy of the source table still holds tenant data and still
# refreshes. Harmless to the rule as it stands, but it is one careless relationship away from
# becoming a second, unfiltered path to the same rows.
$stale = @($tenantTables | Where-Object { $_ -match '(?i)(old|copy|backup|bak|tmp|test)' })
if ($stale.Count -gt 0) {
    Write-Host ""
    Write-Host "Left-behind tables still carrying tenant data:" -ForegroundColor Yellow
    $stale | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

$srv.Disconnect()

$bad = $missing.Count + $noPerm.Count + $noScope.Count
if ($bad -gt 0) {
    Write-Host ""
    foreach ($n in $missing) { Write-Host "  NO FILTER     $n" -ForegroundColor Red }
    foreach ($n in $noPerm)  { Write-Host "  NO USER TEST  $n" -ForegroundColor Red }
    foreach ($n in $noScope) { Write-Host "  NO CUSTOMDATA $n  (will show every permitted tenant added together)" -ForegroundColor Red }
    exit 1
}
Write-Host ""
Write-Host "OK -- every tenant-bearing table filters on both the user and the selected practice." -ForegroundColor Green
exit 0
