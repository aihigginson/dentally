# ---------------------------------------------------------------------------
# Migrate.ps1  --  ordered, tracked, forward-only database migrations.
# ---------------------------------------------------------------------------
# Applies pending Migrations/Vnnn__*.sql files in version order, exactly once
# each, recording them in Migrate.Schema_Version. Idempotent: re-running only
# applies new migrations. Authenticates as the Test Runner service principal
# (same creds as Run_Tests.ps1) via an AAD token + .NET SqlClient.
#
# This is the structured alternative to the ad-hoc Scripts/Deploy_*.ps1 scripts:
# migrations carry ordered, once-only, DATA-PRESERVING schema/data changes (e.g.
# ALTER TABLE ADD COLUMN) so existing environments move forward without a
# DROP/CREATE rebuild. Idempotent objects (procs, views, functions) and
# re-seedable data still deploy from their Fabric/*.sql files. See
# Migrations/README.md for the full regime + release workflow.
#
# Usage:  .\Scripts\Migrate.ps1            # apply all pending migrations
#         .\Scripts\Migrate.ps1 -WhatIf    # list pending, apply nothing
# Exit:   0 = up to date / applied ok ; 1 = a migration failed ; 2 = config/conn.
# ---------------------------------------------------------------------------

param([switch] $WhatIf)
$ErrorActionPreference = 'Stop'

$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET
$Server   = if ($env:FABRIC_SERVER) { $env:FABRIC_SERVER } else { 'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com' }
$Database = if ($env:FABRIC_DB)     { $env:FABRIC_DB }     else { 'WH_Dentally' }
if (-not ($Tenant -and $ClientId -and $Secret)) { Write-Host 'Missing FABRIC_SP_* creds.' -ForegroundColor Red; exit 2 }

$MigDir = Join-Path $PSScriptRoot '..\Migrations'

$body = @{ grant_type='client_credentials'; client_id=$ClientId; client_secret=$Secret; scope='https://database.windows.net/.default' }
try { $tok = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body).access_token }
catch { Write-Host "Token request failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
$conn.AccessToken = $tok
try { $conn.Open() } catch { Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
Write-Host "Connected to $Database @ $Server" -ForegroundColor Green

function Exec1([string] $sql, [int] $timeout = 300) { $c = $conn.CreateCommand(); $c.CommandText = $sql; $c.CommandTimeout = $timeout; [void] $c.ExecuteNonQuery() }
function ExecBatches([string] $sql) { foreach ($b in [regex]::Split($sql, "(?im)^\s*GO\s*$")) { if ($b.Trim().Length -gt 0) { Exec1 $b } } }

# Tracking table (idempotent).
Exec1 "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name='Migrate') EXEC('CREATE SCHEMA [Migrate]')"
Exec1 @"
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name='Migrate' AND t.name='Schema_Version')
  CREATE TABLE Migrate.Schema_Version (Version varchar(20) NOT NULL, Name varchar(200) NOT NULL, Checksum varchar(64) NULL, Applied_At datetime2(3) NOT NULL, Success bit NOT NULL)
"@

# Already-applied versions.
$applied = @{}
$cmd = $conn.CreateCommand(); $cmd.CommandText = "SELECT Version FROM Migrate.Schema_Version WHERE Success = 1"
$rdr = $cmd.ExecuteReader(); while ($rdr.Read()) { $applied[[string]$rdr.GetValue(0)] = $true }; $rdr.Close()

# Pending migration files, in version order.
$pending = @()
foreach ($f in (Get-ChildItem (Join-Path $MigDir 'V*.sql') -ErrorAction SilentlyContinue | Sort-Object Name)) {
    if ($f.Name -match '^(V\d+)__(.+)\.sql$') {
        $ver = $Matches[1]; $name = $Matches[2]
        if (-not $applied.ContainsKey($ver)) { $pending += [pscustomobject]@{ Version = $ver; Name = $name; Path = $f.FullName } }
    }
}

if ($pending.Count -eq 0) { Write-Host "No pending migrations -- database is up to date." -ForegroundColor Green; $conn.Close(); exit 0 }
Write-Host "Pending migrations: $($pending.Count)" -ForegroundColor Cyan
$pending | ForEach-Object { Write-Host "  $($_.Version)  $($_.Name)" }
if ($WhatIf) { Write-Host "-WhatIf: nothing applied." -ForegroundColor Yellow; $conn.Close(); exit 0 }

$sha = New-Object System.Security.Cryptography.SHA256Managed
foreach ($m in $pending) {
    Write-Host "Applying $($m.Version)  $($m.Name) ..." -ForegroundColor Cyan
    $sql  = [System.IO.File]::ReadAllText($m.Path)
    $hash = ([System.BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sql))) -replace '-').ToLower()
    $vn = $m.Version.Replace("'","''"); $nm = $m.Name.Replace("'","''")
    try {
        ExecBatches $sql
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        try { Exec1 "INSERT INTO Migrate.Schema_Version (Version,Name,Checksum,Applied_At,Success) VALUES ('$vn','$nm','$hash',SYSUTCDATETIME(),0)" } catch {}
        $conn.Close(); exit 1
    }
    Exec1 "INSERT INTO Migrate.Schema_Version (Version,Name,Checksum,Applied_At,Success) VALUES ('$vn','$nm','$hash',SYSUTCDATETIME(),1)"
    Write-Host "  OK" -ForegroundColor Green
}

$conn.Close()
Write-Host "All migrations applied." -ForegroundColor Green
exit 0
