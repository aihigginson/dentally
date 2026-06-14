# ---------------------------------------------------------------------------
# Deploy.ps1  --  standard, manifest-driven warehouse deployment.
# ---------------------------------------------------------------------------
# One runner for every warehouse release. Instead of a bespoke Deploy_*.ps1
# per change, a release is described by an ordered MANIFEST (Releases/*.manifest)
# that lists what to run, in order, tagged by action type. The manifest ships
# WITH the release (versioned in git, reviewable in the PR diff).
#
# Authenticates as the Test Runner service principal (same creds as
# Run_Tests.ps1 / Migrate.ps1) via an AAD token + .NET SqlClient -- no
# interactive sign-in, so it runs locally and in CI unchanged.
#
# Manifest format (one action per line; blank lines and # comments ignored):
#   TAG  <argument>
#
#   MIGRATE  <path>   Apply a tracked, once-only schema delta. Recorded in
#                     Migrate.Schema_Version and SKIPPED if already applied.
#                     Use for data-preserving table changes (ALTER ... ADD).
#                     File must be named Vnnn__<name>.sql.
#   DEPLOY   <path>   Execute a SQL object file's batches (split on GO). For
#                     idempotent DROP/CREATE objects (procs, views, functions)
#                     and re-seedable data (TRUNCATE+INSERT). i.e. LOAD a proc.
#   EXEC     <tsql>   Run an inline T-SQL batch. i.e. RUN a proc / reload /
#                     backfill / regenerate views. The whole remainder of the
#                     line is sent as one batch (declare OUT params inline).
#   TEST    [plain]   Run Scripts\Run_Tests.ps1 as a gate (no -Promote;
#                     promotion stays a deliberate human step). Fails the
#                     deploy if the tests fail.
#
# Usage:
#   .\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest
#   .\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest -WhatIf
# Exit:  0 = applied ok ; 1 = an action failed ; 2 = config / connection / parse.
# ---------------------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)][string] $Manifest,
    [switch] $WhatIf
)
$ErrorActionPreference = 'Stop'

# --- creds (gitignored local file for dev; env vars / GitHub secrets in CI) -
$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET
$Server   = if ($env:FABRIC_SERVER) { $env:FABRIC_SERVER } else { 'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com' }
$Database = if ($env:FABRIC_DB)     { $env:FABRIC_DB }     else { 'WH_Dentally' }
if (-not ($Tenant -and $ClientId -and $Secret)) { Write-Host 'Missing FABRIC_SP_* creds.' -ForegroundColor Red; exit 2 }

$RepoRoot = Split-Path $PSScriptRoot -Parent

function Resolve-RepoPath([string] $p) {
    $p = $p -replace '[\\/]', '\'
    if (Test-Path $p) { return (Resolve-Path $p).Path }
    $rp = Join-Path $RepoRoot $p
    if (Test-Path $rp) { return (Resolve-Path $rp).Path }
    throw "file not found: $p"
}

# --- resolve + parse the manifest into an ordered action list --------------
if (-not (Test-Path $Manifest)) { $Manifest = Join-Path $RepoRoot $Manifest }
if (-not (Test-Path $Manifest)) { Write-Host "Manifest not found: $Manifest" -ForegroundColor Red; exit 2 }

$valid   = @('MIGRATE', 'DEPLOY', 'EXEC', 'TEST')
$actions = @()
$n = 0
foreach ($raw in [System.IO.File]::ReadAllLines($Manifest)) {
    $n++
    $line = $raw.Trim()
    if ($line.Length -eq 0 -or $line.StartsWith('#')) { continue }
    if ($line -match '^(\S+)\s+(.*)$') { $tag = $Matches[1].ToUpper(); $arg = $Matches[2].Trim() }
    else                               { $tag = $line.ToUpper();        $arg = '' }
    if ($valid -notcontains $tag) { Write-Host "Line ${n}: unknown tag '$tag'. Valid: $($valid -join ', ')" -ForegroundColor Red; exit 2 }
    $actions += [pscustomobject]@{ Line = $n; Tag = $tag; Arg = $arg }
}

Write-Host "Manifest: $Manifest  ($($actions.Count) actions)" -ForegroundColor Cyan
if ($WhatIf) {
    $i = 0
    $actions | ForEach-Object { $i++; Write-Host ("  {0,2}. [{1,-7}] {2}" -f $i, $_.Tag, $_.Arg) }
    Write-Host "-WhatIf: nothing executed." -ForegroundColor Yellow
    exit 0
}

# --- connect (SP token + SqlClient) ----------------------------------------
$body = @{ grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $Secret; scope = 'https://database.windows.net/.default' }
try { $tok = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body).access_token }
catch { Write-Host "Token request failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

function Open-Conn {
    $c = New-Object System.Data.SqlClient.SqlConnection
    $c.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
    $c.AccessToken = $tok
    $c.Open()
    return $c
}
try { $conn = Open-Conn } catch { Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
Write-Host "Connected to $Database @ $Server" -ForegroundColor Green

function Exec1([string] $sql, [int] $to = 600) { $c = $conn.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = $to; [void] $c.ExecuteNonQuery() }
function ExecBatches([string] $sql) {
    foreach ($b in [regex]::Split($sql, "(?im)^\s*GO\s*$")) {
        $t = $b.Trim()
        if ($t.Length -eq 0) { continue }
        if ($t -match '^(?i)SET\s+(ANSI_NULLS|QUOTED_IDENTIFIER)\s+(ON|OFF)\s*$') { continue }  # Fabric defaults ON; not valid standalone
        Exec1 $b
    }
}

# Migration tracking table (idempotent) -- shared with Migrate.ps1.
Exec1 "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='Migrate') EXEC('CREATE SCHEMA [Migrate]')"
Exec1 @"
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name='Migrate' AND t.name='Schema_Version')
  CREATE TABLE Migrate.Schema_Version (Version varchar(20) NOT NULL, Name varchar(200) NOT NULL, Checksum varchar(64) NULL, Applied_At datetime2(3) NOT NULL, Success bit NOT NULL)
"@
function Test-Applied([string] $ver) {
    $c = $conn.CreateCommand(); $c.CommandText = "SELECT COUNT(*) FROM Migrate.Schema_Version WHERE Version = '$($ver.Replace("'","''"))' AND Success = 1"
    return ([int] $c.ExecuteScalar()) -gt 0
}

$sha  = New-Object System.Security.Cryptography.SHA256Managed
$step = 0
foreach ($a in $actions) {
    $step++
    $tag = "[$step/$($actions.Count)] $($a.Tag)"
    switch ($a.Tag) {

        'MIGRATE' {
            $path  = Resolve-RepoPath $a.Arg
            $fname = Split-Path $path -Leaf
            if ($fname -notmatch '^(V\d+)__(.+)\.sql$') { Write-Host "$tag  bad migration filename: $fname (expected Vnnn__name.sql)" -ForegroundColor Red; $conn.Close(); exit 1 }
            $ver = $Matches[1]; $nm = $Matches[2]
            if (Test-Applied $ver) { Write-Host "$tag  $fname -- already applied, skipped" -ForegroundColor DarkGray; break }
            Write-Host "$tag  applying $fname ..." -ForegroundColor Cyan
            $sql  = [System.IO.File]::ReadAllText($path)
            $hash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sql))) -replace '-').ToLower()
            $vn = $ver.Replace("'", "''"); $nme = $nm.Replace("'", "''")
            try { ExecBatches $sql }
            catch {
                Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
                try { Exec1 "INSERT INTO Migrate.Schema_Version (Version,Name,Checksum,Applied_At,Success) VALUES ('$vn','$nme','$hash',SYSUTCDATETIME(),0)" } catch {}
                $conn.Close(); exit 1
            }
            Exec1 "INSERT INTO Migrate.Schema_Version (Version,Name,Checksum,Applied_At,Success) VALUES ('$vn','$nme','$hash',SYSUTCDATETIME(),1)"
            Write-Host "  OK" -ForegroundColor Green
        }

        'DEPLOY' {
            $path = Resolve-RepoPath $a.Arg
            Write-Host "$tag  $(Split-Path $path -Leaf)" -ForegroundColor Cyan
            try { ExecBatches ([System.IO.File]::ReadAllText($path)) }
            catch { Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red; $conn.Close(); exit 1 }
            Write-Host "  OK" -ForegroundColor Green
        }

        'EXEC' {
            Write-Host "$tag  $($a.Arg)" -ForegroundColor Cyan
            try { Exec1 $a.Arg 600 }
            catch { Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red; $conn.Close(); exit 1 }
            Write-Host "  OK" -ForegroundColor Green
        }

        'TEST' {
            Write-Host "$tag  running Run_Tests.ps1 gate ..." -ForegroundColor Cyan
            $conn.Close()  # Run_Tests opens its own connection
            & (Join-Path $PSScriptRoot 'Run_Tests.ps1')
            if ($LASTEXITCODE -ne 0) { Write-Host "  TESTS FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
            $conn = Open-Conn  # reopen in case more actions follow
            Write-Host "  OK" -ForegroundColor Green
        }
    }
}

$conn.Close()
Write-Host "Manifest applied successfully." -ForegroundColor Green
exit 0
