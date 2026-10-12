# ---------------------------------------------------------------------------
# List_Model_Relationships.ps1  --  every relationship in the semantic model, with the
# auto-detect debris flagged.
# ---------------------------------------------------------------------------
# WHY THIS EXISTS. Adding a table in Power BI Desktop triggers automatic relationship
# detection, which links on any same-named column it finds -- Tenant ID, Practitioner ID,
# Site ID. Those are business keys, unique only WITHIN a tenant (and Tenant ID is not even
# unique within a table once a practice has two sites). The model carried several of these
# harmlessly for as long as every tenant had one site and no two tenants numbered their
# practitioners the same. Tenant 12 broke both assumptions at once and refresh now fails --
# but it fails on ONE column per attempt, so clearing them by refresh-and-see costs a refresh
# per relationship. This lists the lot in one go.
#
# A refresh-breaking relationship is one whose ONE side is a column that is not unique. The
# intended joins are all surrogate keys: pk Practitioner, pk Practice Site, pk Patient, pk Date.
# Anything with a business key or Tenant ID on the one side is a candidate for deletion.
#
# Auth: service principal (FABRIC_SP_*) when those are set -- the same credentials
# Check_RLS_Coverage.ps1 uses -- otherwise an INTERACTIVE sign-in, which needs a desktop
# session and a browser. A delegated `az` token does NOT work here: the Azure CLI's client is
# not authorised for the Power BI XMLA endpoint.
#
# Usage:
#   .\Scripts\List_Model_Relationships.ps1
#   .\Scripts\List_Model_Relationships.ps1 -WsName 'DM Dentally'          # prod
#   .\Scripts\List_Model_Relationships.ps1 -All                           # don't just flag, show all
# ---------------------------------------------------------------------------
param(
    [string] $WsName = 'DEV - DM Dentally',
    [string] $DsName = 'PBI Dentally',
    [switch] $All
)

$adomd = $env:ADOMD_DLL
if (-not $adomd -or -not (Test-Path $adomd)) {
    $adomd = (Get-ChildItem "$env:LOCALAPPDATA\ADOMD.NET", "$env:ProgramFiles\Microsoft.NET\ADOMD.NET" `
                -Recurse -Filter 'Microsoft.AnalysisServices.AdomdClient.dll' -ErrorAction SilentlyContinue |
              Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName)
}
if (-not $adomd -or -not (Test-Path $adomd)) {
    Write-Host 'ADOMD.NET not found. Set ADOMD_DLL, or install it under %LOCALAPPDATA%\ADOMD.NET.' -ForegroundColor Red
    exit 2
}
Add-Type -Path $adomd

$ds = "powerbi://api.powerbi.com/v1.0/myorg/$WsName"
if ($env:FABRIC_SP_TENANT -and $env:FABRIC_SP_CLIENT_ID -and $env:FABRIC_SP_CLIENT_SECRET) {
    $connStr = "Data Source=$ds;Initial Catalog=$DsName;User ID=app:$($env:FABRIC_SP_CLIENT_ID)@$($env:FABRIC_SP_TENANT);Password=$($env:FABRIC_SP_CLIENT_SECRET);"
    Write-Host 'Authenticating as the service principal.' -ForegroundColor DarkGray
} else {
    $connStr = "Data Source=$ds;Initial Catalog=$DsName;"
    Write-Host 'FABRIC_SP_* not set -- falling back to an INTERACTIVE sign-in (a browser will open).' -ForegroundColor Yellow
}

$conn = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection($connStr)
try { $conn.Open() } catch { Write-Host "XMLA connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
Write-Host "Connected to '$DsName' in '$WsName'.`n" -ForegroundColor Green

$sql = @"
SELECT  tf.[Name] AS FromTable, cf.[ExplicitName] AS FromColumn,
        tt.[Name] AS ToTable,   ct.[ExplicitName] AS ToColumn,
        r.[IsActive], r.[FromCardinality], r.[ToCardinality], r.[CrossFilteringBehavior]
FROM    `$SYSTEM.TMSCHEMA_RELATIONSHIPS r
JOIN    `$SYSTEM.TMSCHEMA_TABLES  tf ON tf.[ID] = r.[FromTableID]
JOIN    `$SYSTEM.TMSCHEMA_COLUMNS cf ON cf.[ID] = r.[FromColumnID]
JOIN    `$SYSTEM.TMSCHEMA_TABLES  tt ON tt.[ID] = r.[ToTableID]
JOIN    `$SYSTEM.TMSCHEMA_COLUMNS ct ON ct.[ID] = r.[ToColumnID]
"@
$cmd = $conn.CreateCommand(); $cmd.CommandText = $sql
$da = New-Object Microsoft.AnalysisServices.AdomdClient.AdomdDataAdapter($cmd)
$dt = New-Object System.Data.DataTable
[void]$da.Fill($dt)

# Cardinality 1 = one, 2 = many. The ONE side is the column that must be unique.
$rows = foreach ($r in $dt) {
    $oneTable  = if ($r.FromCardinality -eq 1) { $r.FromTable }  else { $r.ToTable }
    $oneColumn = if ($r.FromCardinality -eq 1) { $r.FromColumn } else { $r.ToColumn }
    $suspect = ($oneColumn -notlike 'pk *') -and ($oneColumn -ne 'Date')
    [pscustomobject]@{
        Suspect   = $suspect
        OneSide   = "$oneTable[$oneColumn]"
        ManySide  = if ($r.FromCardinality -eq 1) { "$($r.ToTable)[$($r.ToColumn)]" }
                    else { "$($r.FromTable)[$($r.FromColumn)]" }
        Active    = $r.IsActive
    }
}

$bad = @($rows | Where-Object Suspect)
Write-Host ("{0} relationship(s) total; {1} with a NON-SURROGATE column on the one side." -f $rows.Count, $bad.Count) -ForegroundColor Cyan
Write-Host "These are the refresh-breakers -- each must be unique, and a business key is not.`n" -ForegroundColor Cyan
$bad | Sort-Object OneSide | Format-Table OneSide, ManySide, Active -AutoSize

if ($All) {
    Write-Host "`nAll relationships:" -ForegroundColor DarkGray
    $rows | Sort-Object Suspect, OneSide | Format-Table Suspect, OneSide, ManySide, Active -AutoSize
}
$conn.Close()
