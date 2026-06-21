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
# Every real run is stamped into Migrate.Deploy_Log (release manifest, git
# commit SHA, branch, who, when, status) so a deploy is auditable and the
# exact pre-deploy code revision is recoverable for a rollback. See
# Releases/README.md "Rolling back a release".
#
# Usage:
#   .\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest
#   .\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest -WhatIf
#   .\Scripts\Deploy.ps1 -Manifest Releases\V001__patient_cohorts.manifest -Log
# Exit:  0 = applied ok ; 1 = an action failed ; 2 = config / connection / parse.
# ---------------------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)][string] $Manifest,
    [switch] $WhatIf,
    [switch] $Log
)
$ErrorActionPreference = 'Stop'

# --- creds (gitignored local file for dev; env vars / GitHub secrets in CI) -
$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET
$PreToken = $env:FABRIC_ACCESS_TOKEN   # OIDC/CI: a pre-acquired AAD token for the warehouse (no client secret)
$Server   = if ($env:FABRIC_SERVER) { $env:FABRIC_SERVER } else { 'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com' }
$Database = if ($env:FABRIC_DB)     { $env:FABRIC_DB }     else { 'WH_Dentally' }
# Auth is either a pre-acquired token (FABRIC_ACCESS_TOKEN, e.g. from a GitHub OIDC
# login -> az account get-access-token) or an SP client-credentials grant
# (FABRIC_SP_TENANT/CLIENT_ID/CLIENT_SECRET). Prod CI uses the former (no stored secret).
if (-not $PreToken -and -not ($Tenant -and $ClientId -and $Secret)) {
    Write-Host 'Missing credentials: set FABRIC_ACCESS_TOKEN, or FABRIC_SP_TENANT/CLIENT_ID/CLIENT_SECRET.' -ForegroundColor Red; exit 2
}

$RepoRoot = Split-Path $PSScriptRoot -Parent

function Resolve-RepoPath([string] $p) {
    $p = $p -replace '[\\/]', '\'
    if (Test-Path $p) { return (Resolve-Path $p).Path }
    $rp = Join-Path $RepoRoot $p
    if (Test-Path $rp) { return (Resolve-Path $rp).Path }
    throw "file not found: $p"
}
function SqlLit([string] $s) { if ($null -eq $s) { return '' } return $s.Replace("'", "''") }

# --- resolve + parse the manifest into an ordered action list --------------
if (-not (Test-Path $Manifest)) { $Manifest = Join-Path $RepoRoot $Manifest }
if (-not (Test-Path $Manifest)) { Write-Host "Manifest not found: $Manifest" -ForegroundColor Red; exit 2 }
# Make absolute: [System.IO.File] calls below resolve relative paths against the
# .NET process cwd (often the user's home dir), not the PowerShell location.
$Manifest = (Resolve-Path $Manifest).Path
$manifestLeaf = Split-Path $Manifest -Leaf

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
if ($PreToken) {
    # Token already acquired upstream (e.g. GitHub OIDC login -> az account get-access-token
    # --resource https://database.windows.net). No client secret involved.
    $tok = $PreToken
} else {
    $body = @{ grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $Secret; scope = 'https://database.windows.net/.default' }
    try { $tok = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body).access_token }
    catch { Write-Host "Token request failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
}

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

# Tracking tables (idempotent). Schema_Version is shared with Migrate.ps1;
# Deploy_Log is the per-deploy audit ledger (the rollback "helping hand").
Exec1 "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='Migrate') EXEC('CREATE SCHEMA [Migrate]')"
Exec1 @"
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name='Migrate' AND t.name='Schema_Version')
  CREATE TABLE Migrate.Schema_Version (Version varchar(20) NOT NULL, Name varchar(200) NOT NULL, Checksum varchar(64) NULL, Applied_At datetime2(3) NOT NULL, Success bit NOT NULL)
"@
Exec1 @"
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name='Migrate' AND t.name='Deploy_Log')
  CREATE TABLE Migrate.Deploy_Log (Deploy_Id varchar(36) NOT NULL, Manifest varchar(260) NOT NULL, Git_Commit varchar(40) NULL, Git_Branch varchar(200) NULL, Deployed_By varchar(200) NULL, Deployed_At datetime2(3) NOT NULL, Action_Count int NULL, Status varchar(20) NOT NULL)
"@
function Test-Applied([string] $ver) {
    $c = $conn.CreateCommand(); $c.CommandText = "SELECT COUNT(*) FROM Migrate.Schema_Version WHERE Version = '$(SqlLit $ver)' AND Success = 1"
    return ([int] $c.ExecuteScalar()) -gt 0
}

# --- -Log : show this manifest's deploy history + file list, then exit -----
if ($Log) {
    Write-Host "Deploy history for '$manifestLeaf':" -ForegroundColor Cyan
    $c = $conn.CreateCommand()
    $c.CommandText = "SELECT Deployed_At, Status, Git_Branch, Git_Commit, Deployed_By, Action_Count FROM Migrate.Deploy_Log WHERE Manifest = '$(SqlLit $manifestLeaf)' ORDER BY Deployed_At DESC"
    $r = $c.ExecuteReader(); $any = $false
    while ($r.Read()) {
        $any = $true
        $shaFull = [string] $r['Git_Commit']
        $shaShort = if ($shaFull.Length -ge 8) { $shaFull.Substring(0, 8) } else { $shaFull }
        Write-Host ("  {0:yyyy-MM-dd HH:mm:ss}  {1,-8} {2}@{3}  by {4}  ({5} actions)" -f `
            [datetime] $r['Deployed_At'], [string] $r['Status'], [string] $r['Git_Branch'], $shaShort, [string] $r['Deployed_By'], $r['Action_Count'])
    }
    $r.Close()
    if (-not $any) { Write-Host "  (no deploys recorded)" -ForegroundColor DarkGray }
    Write-Host "Files in this manifest (revert candidates for rollback):" -ForegroundColor Cyan
    $actions | Where-Object { $_.Tag -eq 'MIGRATE' -or $_.Tag -eq 'DEPLOY' } | ForEach-Object { Write-Host ("  [{0,-7}] {1}" -f $_.Tag, $_.Arg) }
    $conn.Close(); exit 0
}

# --- capture deploy provenance + open the ledger row -----------------------
$gitSha = ''; $gitBranch = ''
try { $gitSha    = (& git -C $RepoRoot rev-parse HEAD).Trim() }            catch { $gitSha = '' }
try { $gitBranch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim() } catch { $gitBranch = '' }
$who = if ($env:GITHUB_ACTOR) { $env:GITHUB_ACTOR } elseif ($env:USERNAME) { $env:USERNAME } else { 'unknown' }
$deployId = [guid]::NewGuid().ToString()
Exec1 "INSERT INTO Migrate.Deploy_Log (Deploy_Id,Manifest,Git_Commit,Git_Branch,Deployed_By,Deployed_At,Action_Count,Status) VALUES ('$deployId','$(SqlLit $manifestLeaf)','$(SqlLit $gitSha)','$(SqlLit $gitBranch)','$(SqlLit $who)',SYSUTCDATETIME(),$($actions.Count),'RUNNING')"
$shaLabel = if ($gitSha.Length -ge 8) { $gitSha.Substring(0, 8) } else { '(no git)' }
Write-Host "Deploy $deployId  commit $shaLabel  branch $gitBranch" -ForegroundColor DarkGray

$sha  = New-Object System.Security.Cryptography.SHA256Managed
$step = 0
try {
    foreach ($a in $actions) {
        $step++
        $tag = "[$step/$($actions.Count)] $($a.Tag)"
        switch ($a.Tag) {

            'MIGRATE' {
                $path  = Resolve-RepoPath $a.Arg
                $fname = Split-Path $path -Leaf
                if ($fname -notmatch '^(V\d+)__(.+)\.sql$') { throw "$tag bad migration filename: $fname (expected Vnnn__name.sql)" }
                $ver = $Matches[1]; $nm = $Matches[2]
                if (Test-Applied $ver) { Write-Host "$tag  $fname -- already applied, skipped" -ForegroundColor DarkGray; break }
                Write-Host "$tag  applying $fname ..." -ForegroundColor Cyan
                $sql  = [System.IO.File]::ReadAllText($path)
                $hash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sql))) -replace '-').ToLower()
                $vn = SqlLit $ver; $nme = SqlLit $nm
                try { ExecBatches $sql }
                catch {
                    try { Exec1 "INSERT INTO Migrate.Schema_Version (Version,Name,Checksum,Applied_At,Success) VALUES ('$vn','$nme','$hash',SYSUTCDATETIME(),0)" } catch {}
                    throw "MIGRATE $fname failed: $($_.Exception.Message)"
                }
                Exec1 "INSERT INTO Migrate.Schema_Version (Version,Name,Checksum,Applied_At,Success) VALUES ('$vn','$nme','$hash',SYSUTCDATETIME(),1)"
                Write-Host "  OK" -ForegroundColor Green
            }

            'DEPLOY' {
                $path = Resolve-RepoPath $a.Arg
                Write-Host "$tag  $(Split-Path $path -Leaf)" -ForegroundColor Cyan
                try { ExecBatches ([System.IO.File]::ReadAllText($path)) }
                catch { throw "DEPLOY $(Split-Path $path -Leaf) failed: $($_.Exception.Message)" }
                Write-Host "  OK" -ForegroundColor Green
            }

            'EXEC' {
                Write-Host "$tag  $($a.Arg)" -ForegroundColor Cyan
                try { Exec1 $a.Arg 600 }
                catch { throw "EXEC failed: $($_.Exception.Message)" }
                Write-Host "  OK" -ForegroundColor Green
            }

            'TEST' {
                Write-Host "$tag  running Run_Tests.ps1 gate ..." -ForegroundColor Cyan
                & (Join-Path $PSScriptRoot 'Run_Tests.ps1')   # opens its own connection; ours stays open
                if ($LASTEXITCODE -ne 0) { throw "Run_Tests gate failed (exit $LASTEXITCODE)" }
                Write-Host "  OK" -ForegroundColor Green
            }
        }
    }
}
catch {
    Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
    try { Exec1 "UPDATE Migrate.Deploy_Log SET Status='FAILED' WHERE Deploy_Id='$deployId'" } catch {}
    try { $conn.Close() } catch {}
    exit 1
}

Exec1 "UPDATE Migrate.Deploy_Log SET Status='SUCCESS' WHERE Deploy_Id='$deployId'"
$conn.Close()
Write-Host "Manifest applied successfully.  (deploy $deployId, commit $shaLabel)" -ForegroundColor Green
exit 0
