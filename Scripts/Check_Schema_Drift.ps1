# ---------------------------------------------------------------------------
# Check_Schema_Drift.ps1  --  repo Fabric\*.Table.sql  vs  live warehouse schema.
# ---------------------------------------------------------------------------
# The *.Table.sql files are the source of truth for table shape. Fabric CANNOT
# ALTER COLUMN a width/type, so a DDL that was widened but whose live table was
# never recreated leaves the live column narrow -> a latent 8152 "String or
# binary data would be truncated" on the first real value that overflows (the
# Preferred_Phone / Contract_Targets_String saga). This guard parses every
# CREATE TABLE, reads live sys.columns, and reports any column whose live TYPE
# or WIDTH differs from the repo -- so drift is caught on deploy, not months on.
#
# Auth: same model as Deploy.ps1. Point it at whichever environment to check:
#   - dev : gitignored Scripts\fabric_creds.local.ps1 (SP secret), or FABRIC_SP_*
#   - prod: a pre-acquired token in FABRIC_ACCESS_TOKEN + FABRIC_SERVER=<prod>
#
# Usage:
#   .\Scripts\Check_Schema_Drift.ps1
#   .\Scripts\Check_Schema_Drift.ps1 -IncludeExtra   # also list live-only columns
# Exit:  0 = in sync ; 1 = drift (type / width / missing) ; 2 = config / connection.
# ---------------------------------------------------------------------------
param(
    [switch] $IncludeExtra,   # also report columns that exist live but not in the repo DDL
    [switch] $Quiet           # suppress the "OK" per-clean-table noise (only drift + summary)
)
$ErrorActionPreference = 'Stop'

# --- creds (gitignored local file for dev; env vars / secrets in CI) --------
$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET
$PreToken = $env:FABRIC_ACCESS_TOKEN
$Server   = if ($env:FABRIC_SERVER) { $env:FABRIC_SERVER } else { 'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com' }
$Database = if ($env:FABRIC_DB)     { $env:FABRIC_DB }     else { 'WH_Dentally' }

if (-not $PreToken -and -not ($Tenant -and $ClientId -and $Secret)) {
    Write-Host 'Missing credentials: set FABRIC_ACCESS_TOKEN, or FABRIC_SP_TENANT/CLIENT_ID/CLIENT_SECRET.' -ForegroundColor Red; exit 2
}

$RepoRoot = Split-Path $PSScriptRoot -Parent

# --- parse the repo DDLs ----------------------------------------------------
# string/binary types whose declared length we compare against live max_length
$LenTypes = @('varchar','char','varbinary','binary','nvarchar','nchar')

function Get-RepoLen([string] $type, [string] $len) {
    if ($LenTypes -notcontains $type) { return $null }          # non-string: don't length-check
    if ($null -eq $len -or $len.Trim() -eq '') { return $null }
    if ($len -match '(?i)max') { return -1 }                    # VARCHAR(MAX) -> live max_length -1
    $n = ($len -split ',')[0].Trim()
    $out = 0
    if (-not [int]::TryParse($n, [ref] $out)) { return $null }
    if ($type -eq 'nvarchar' -or $type -eq 'nchar') { return $out * 2 }  # live max_length is bytes
    return $out
}
function Fmt-Len($v) { if ($null -eq $v) { return '-' } elseif ($v -eq -1) { return 'MAX' } else { return "$v" } }

$repo = @{}
$tableFiles = Get-ChildItem (Join-Path $RepoRoot 'Fabric') -Filter '*.Table.sql'
foreach ($f in $tableFiles) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    $m = [regex]::Match($text, '(?is)CREATE\s+TABLE\s+\[(?<sch>[^\]]+)\]\.\[(?<tbl>[^\]]+)\]')
    if (-not $m.Success) { continue }
    $sch = $m.Groups['sch'].Value
    $tbl = $m.Groups['tbl'].Value
    foreach ($line in ($text -split "`n")) {
        # column line: [Name] [type] optionally (len[, scale])
        $cm = [regex]::Match($line, '^\s*\[(?<col>[^\]]+)\]\s*\[(?<type>[^\]]+)\]\s*(?:\(\s*(?<len>[^)]+?)\s*\))?')
        if (-not $cm.Success) { continue }
        $col  = $cm.Groups['col'].Value
        $type = $cm.Groups['type'].Value.ToLower()
        $len  = $cm.Groups['len'].Value
        $repo["$sch.$tbl.$col"] = [pscustomobject]@{
            Schema = $sch; Table = $tbl; Column = $col; Type = $type; Len = (Get-RepoLen $type $len)
        }
    }
}
Write-Host ("Parsed {0} columns from {1} Fabric\*.Table.sql files." -f $repo.Count, $tableFiles.Count) -ForegroundColor Cyan

# --- connect + read live schema --------------------------------------------
if ($PreToken) { $tok = $PreToken }
else {
    $body = @{ grant_type='client_credentials'; client_id=$ClientId; client_secret=$Secret; scope='https://database.windows.net/.default' }
    try { $tok = (Invoke-RestMethod -Method Post -ContentType 'application/x-www-form-urlencoded' -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body).access_token }
    catch { Write-Host "Token request failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
}
$conn = New-Object System.Data.SqlClient.SqlConnection
$conn.ConnectionString = "Server=$Server;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;"
$conn.AccessToken = $tok
try { $conn.Open() } catch { Write-Host "Connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
Write-Host "Connected to $Database @ $Server" -ForegroundColor Green

$live = @{}
$cmd = $conn.CreateCommand()
$cmd.CommandText = @"
SELECT s.name AS Sch, t.name AS Tbl, c.name AS Col, ty.name AS Typ, c.max_length AS Len
FROM sys.columns c
JOIN sys.tables   t  ON t.object_id     = c.object_id
JOIN sys.schemas  s  ON s.schema_id     = t.schema_id
JOIN sys.types    ty ON ty.user_type_id = c.user_type_id
"@
$rd = $cmd.ExecuteReader()
while ($rd.Read()) {
    $key = "$($rd['Sch']).$($rd['Tbl']).$($rd['Col'])"
    $live[$key] = [pscustomobject]@{ Type = ([string] $rd['Typ']).ToLower(); Len = [int] $rd['Len'] }
}
$rd.Close(); $conn.Close()

# --- diff -------------------------------------------------------------------
$typeDrift = @(); $widthDrift = @(); $missing = @(); $extra = @()
foreach ($key in $repo.Keys) {
    $rp = $repo[$key]
    if (-not $live.ContainsKey($key)) { $missing += $key; continue }
    $lv = $live[$key]
    if ($rp.Type -ne $lv.Type) {
        $typeDrift += [pscustomobject]@{ Key=$key; Repo=$rp.Type; Live=$lv.Type }; continue
    }
    if ($null -ne $rp.Len -and $rp.Len -ne $lv.Len) {
        # live narrower than repo = the dangerous case (truncation waiting to happen)
        $narrower = ($lv.Len -ne -1) -and ($rp.Len -eq -1 -or $lv.Len -lt $rp.Len)
        $widthDrift += [pscustomobject]@{ Key=$key; Repo=(Fmt-Len $rp.Len); Live=(Fmt-Len $lv.Len); Narrower=$narrower }
    }
}
if ($IncludeExtra) {
    $repoTables = @{}
    foreach ($k in $repo.Keys) { $repoTables[(($k -split '\.')[0..1] -join '.')] = $true }
    foreach ($key in $live.Keys) {
        if ($repo.ContainsKey($key)) { continue }
        if ($repoTables.ContainsKey((($key -split '\.')[0..1] -join '.'))) { $extra += $key }  # only tables we own a DDL for
    }
}

# --- report -----------------------------------------------------------------
Write-Host ''
if ($widthDrift.Count -gt 0) {
    Write-Host "WIDTH DRIFT ($($widthDrift.Count)) -- repo DDL width != live column width:" -ForegroundColor Yellow
    foreach ($d in ($widthDrift | Sort-Object { -not $_.Narrower }, Key)) {
        $tag = if ($d.Narrower) { '  [LIVE NARROWER -> 8152 RISK]' } else { '  [repo wider than live? update DDL]' }
        $col = if ($d.Narrower) { 'Red' } else { 'DarkYellow' }
        Write-Host ("  {0}  repo={1}  live={2}{3}" -f $d.Key, $d.Repo, $d.Live, $tag) -ForegroundColor $col
    }
    Write-Host ''
}
if ($typeDrift.Count -gt 0) {
    Write-Host "TYPE DRIFT ($($typeDrift.Count)) -- repo DDL type != live column type:" -ForegroundColor Yellow
    foreach ($d in ($typeDrift | Sort-Object Key)) { Write-Host ("  {0}  repo={1}  live={2}" -f $d.Key, $d.Repo, $d.Live) -ForegroundColor Red }
    Write-Host ''
}
if ($missing.Count -gt 0) {
    Write-Host "IN REPO, NOT LIVE ($($missing.Count)) -- column/table not deployed (or table has no live copy):" -ForegroundColor Yellow
    foreach ($k in ($missing | Sort-Object)) { Write-Host "  $k" -ForegroundColor DarkYellow }
    Write-Host ''
}
if ($IncludeExtra -and $extra.Count -gt 0) {
    Write-Host "LIVE, NOT IN REPO ($($extra.Count)) -- live column with no repo DDL (stale DDL?):" -ForegroundColor DarkGray
    foreach ($k in ($extra | Sort-Object)) { Write-Host "  $k" -ForegroundColor DarkGray }
    Write-Host ''
}

$narrowCount = @($widthDrift | Where-Object { $_.Narrower }).Count
$drift = $typeDrift.Count + $widthDrift.Count + $missing.Count
if ($drift -eq 0) {
    Write-Host "IN SYNC: every repo column matches live ($Database)." -ForegroundColor Green
    $conn.Dispose(); exit 0
}
Write-Host ("DRIFT: {0} width, {1} type, {2} missing ({3} are LIVE-NARROWER = active 8152 risk)." -f `
    $widthDrift.Count, $typeDrift.Count, $missing.Count, $narrowCount) -ForegroundColor Red
Write-Host "Fix: recreate the affected table(s) from the repo *.Table.sql (Fabric can't ALTER a width) + reload -- see V056/V057 for the pattern." -ForegroundColor DarkGray
exit 1
