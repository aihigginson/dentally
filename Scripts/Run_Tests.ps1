# ---------------------------------------------------------------------------
# Run_Tests.ps1  --  deploy + run the Test regression framework and report
# ---------------------------------------------------------------------------
# Self-contained: authenticates a service principal via an Azure AD token
# (client credentials) and connects to the Fabric warehouse through .NET
# SqlClient, so it needs NO interactive sign-in and no sqlcmd auth flags.
# Designed to be run repeatedly while iterating: it exits 0 when every check
# passes and 1 when anything fails, and prints only the failing rows.
#
# Credentials (NEVER commit these) come from environment variables. The
# easiest local setup: copy Scripts/fabric_creds.local.ps1.example to
# Scripts/fabric_creds.local.ps1 (gitignored), fill it in, and this script
# will dot-source it automatically.
#
#   FABRIC_SERVER         warehouse SQL endpoint (defaulted below)
#   FABRIC_DB             database name (default WH_Dentally)
#   FABRIC_SP_TENANT      Azure AD tenant id (or <name>.onmicrosoft.com)
#   FABRIC_SP_CLIENT_ID   service principal application (client) id
#   FABRIC_SP_CLIENT_SECRET   service principal client secret
#   FABRIC_SQL_SCOPE      token scope (default https://database.windows.net/.default)
#
# Usage:
#   .\Scripts\Run_Tests.ps1                 # deploy + capture + compare, report
#   .\Scripts\Run_Tests.ps1 -NoDeploy       # skip re-seeding, just capture+compare
#   .\Scripts\Run_Tests.ps1 -Promote        # if all pass, promote Current -> Baseline
# ---------------------------------------------------------------------------

param(
    [switch] $NoDeploy,
    [switch] $Promote,
    [string] $RunTag = ("run-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
)

$ErrorActionPreference = 'Stop'

# --- Load local creds file if present (gitignored) -------------------------
$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

# --- Resolve settings ------------------------------------------------------
$Server   = if ($env:FABRIC_SERVER) { $env:FABRIC_SERVER } else { 'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com' }
$Database = if ($env:FABRIC_DB)     { $env:FABRIC_DB }     else { 'WH_Dentally' }
$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET
$Scope    = if ($env:FABRIC_SQL_SCOPE) { $env:FABRIC_SQL_SCOPE } else { 'https://database.windows.net/.default' }

$missing = @()
if (-not $Tenant)   { $missing += 'FABRIC_SP_TENANT' }
if (-not $ClientId) { $missing += 'FABRIC_SP_CLIENT_ID' }
if (-not $Secret)   { $missing += 'FABRIC_SP_CLIENT_SECRET' }
if ($missing.Count -gt 0) {
    Write-Host "Missing credentials: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Set them as env vars or in Scripts/fabric_creds.local.ps1" -ForegroundColor Red
    exit 2
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

# --- Acquire an AAD token for the service principal ------------------------
Write-Host "Acquiring token for SP $ClientId ..." -ForegroundColor Cyan
$tokenBody = @{
    grant_type    = 'client_credentials'
    client_id     = $ClientId
    client_secret = $Secret
    scope         = $Scope
}
try {
    $tok = Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' `
        -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $tokenBody
} catch {
    Write-Host "Token request failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
$accessToken = $tok.access_token

# --- Open a connection -----------------------------------------------------
$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
$conn.AccessToken = $accessToken
try {
    $conn.Open()
} catch {
    Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
Write-Host "Connected to $Database @ $Server" -ForegroundColor Green

function Invoke-NonQuery([string] $sql, [int] $timeout = 300) {
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.CommandTimeout = $timeout
    [void] $cmd.ExecuteNonQuery()
}

# Execute a multi-batch script (splits on lines containing only GO).
function Invoke-Script([string] $sql, [string] $label) {
    $batches = [regex]::Split($sql, "(?im)^\s*GO\s*$")
    foreach ($b in $batches) {
        if ($b.Trim().Length -eq 0) { continue }
        try {
            Invoke-NonQuery $b
        } catch {
            Write-Host "  FAILED in ${label}: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }
}

# --- Deploy (re-seed) the framework ----------------------------------------
if (-not $NoDeploy) {
    $files = @(
        'Test.Schema.sql'
        'Test.Metric_Definition.Table.sql'
        'Test.Comparison_Definition.Table.sql'
        'Test.Capture_Baseline.Table.sql'
        'Test.Capture_Current.Table.sql'
        'Test.Compare_Result.Table.sql'
        'Test.Metric_Definition.Data.sql'
        'Test.Comparison_Definition.Data.sql'
        'Test.usp_Run_Captures.StoredProcedure.sql'
        'Test.usp_Compare.StoredProcedure.sql'
        'Test.usp_Promote.StoredProcedure.sql'
    )
    Write-Host "Deploying Test framework ($($files.Count) files)..." -ForegroundColor Cyan
    foreach ($f in $files) {
        $path = Join-Path $FabricDir $f
        if (-not (Test-Path $path)) { Write-Host "  Missing: $path" -ForegroundColor Red; $conn.Close(); exit 2 }
        Invoke-Script ([System.IO.File]::ReadAllText($path)) $f
    }
    Write-Host "  Deployed." -ForegroundColor Green
}

# --- Run captures + compare ------------------------------------------------
Write-Host "Running captures (tag '$RunTag')..." -ForegroundColor Cyan
Invoke-NonQuery "EXEC Test.usp_Run_Captures @Run_Tag = '$RunTag'"
Write-Host "Comparing..." -ForegroundColor Cyan
Invoke-NonQuery "EXEC Test.usp_Compare"

# --- Capture errors (metrics whose SQL failed) -----------------------------
function Read-Rows([string] $sql) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql
    $r = $cmd.ExecuteReader()
    $rows = @()
    while ($r.Read()) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $r.FieldCount; $i++) { $o[$r.GetName($i)] = $r.GetValue($i) }
        $rows += [pscustomobject]$o
    }
    $r.Close()
    return $rows
}

$latest = "(SELECT TOP 1 Run_Id FROM Test.Compare_Result ORDER BY Compare_Run_At DESC)"

$captureErrors = Read-Rows "SELECT Metric_Name, Error_Message FROM Test.Capture_Current WHERE Error_Message IS NOT NULL ORDER BY Metric_Name"
$summary = Read-Rows "SELECT Check_Type, Status, COUNT(*) AS Cnt FROM Test.Compare_Result WHERE Run_Id = $latest GROUP BY Check_Type, Status ORDER BY Check_Type, Status"
# Real failures only. 'NEW (no baseline)' is benign (first run / newly added
# metric) and must NOT block, otherwise the first baseline can never be set.
$failures = Read-Rows @"
SELECT Check_Type, Item_Name, Value_A, Value_B, Expected_Difference, Actual_Difference, Status, Detail
FROM Test.Compare_Result
WHERE Run_Id = $latest
  AND ( (Check_Type = 'RECONCILE'  AND Status <> 'PASS')
     OR (Check_Type = 'REGRESSION' AND Status NOT IN ('OK','OK (null)','NEW (no baseline)')) )
ORDER BY Check_Type, Item_Name
"@
$newRows  = Read-Rows "SELECT COUNT(*) AS Cnt FROM Test.Compare_Result WHERE Run_Id = $latest AND Status = 'NEW (no baseline)'"
$newCount = [int]$newRows[0].Cnt

# --- Report ----------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60)
Write-Host "SUMMARY (run '$RunTag')" -ForegroundColor Cyan
$summary | Format-Table -AutoSize | Out-String | Write-Host
if ($newCount -gt 0) {
    Write-Host "$newCount metric(s) have no baseline yet (benign -- will be captured on promote)." -ForegroundColor Yellow
}

if ($captureErrors.Count -gt 0) {
    Write-Host "CAPTURE ERRORS ($($captureErrors.Count)) -- metric SQL that failed to run:" -ForegroundColor Red
    $captureErrors | Format-Table -AutoSize -Wrap | Out-String | Write-Host
}

$failCount = $failures.Count
if ($failCount -gt 0) {
    Write-Host "FAILURES ($failCount):" -ForegroundColor Red
    $failures | Format-Table -AutoSize -Wrap | Out-String | Write-Host
} else {
    Write-Host "All checks passed." -ForegroundColor Green
}

# --- Optional promote ------------------------------------------------------
if ($Promote) {
    if ($failCount -eq 0 -and $captureErrors.Count -eq 0) {
        Write-Host "Promoting Current -> Baseline (tag '$RunTag')..." -ForegroundColor Cyan
        Invoke-NonQuery "EXEC Test.usp_Promote @Release_Tag = '$RunTag'"
        Write-Host "  Baseline promoted." -ForegroundColor Green
    } else {
        Write-Host "Not promoting: there are failures / capture errors to resolve first." -ForegroundColor Yellow
    }
}

$conn.Close()

if ($failCount -gt 0 -or $captureErrors.Count -gt 0) { exit 1 } else { exit 0 }
