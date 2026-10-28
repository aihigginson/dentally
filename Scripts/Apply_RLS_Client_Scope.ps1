# ---------------------------------------------------------------------------
#  Apply_RLS_Client_Scope.ps1
#
#  Teaches the RLS rule to narrow by the whole ACTING SCOPE, not just one practice.
#
#  ==> THE RULE HAD ONE NARROWING LEVER AND IT WAS SPENT ON THE PRACTICE. <==
#  CUSTOMDATA() carried a single tenant id and was set ONLY when exactly one tenant was in
#  view. A client holding several practices therefore had nothing to narrow by: picking a
#  client moved every one of the app's own screens while the report kept the caller's whole
#  permitted set and ADDED IT UP. A group of four practices showed every practice the support
#  login could see, under the group's name.
#
#  ==> THE SCOPE IS SENT AS A SET, NOT AS A CLIENT ID. <== Sending the client id reads better
#  but needs a client->tenant table in the model to resolve it, and adding a table means adding
#  a data connection -- which the service principal cannot do ("insufficient permissions ...
#  at least Use permissions on all data connections"), and which would be a second place for
#  the access model to drift from Security.Client_Tenant_Access. The app already holds the
#  answer: _get_user_info resolves the acting client's tenants and narrows them by the acting
#  practice, so it sends THAT set and the rule only has to test membership.
#
#  So customData is now a comma-separated tenant set, and the SCOPE half of the rule becomes
#  PATHCONTAINS over it. One tenant renders as a bare "11" -- byte-for-byte the old form -- so
#  old and new app versions both work against either rule during a deploy, and a blank
#  CUSTOMDATA still means "everything I may see", unchanged.
#
#  It narrows and never widens: the USERPRINCIPALNAME set-membership half is untouched and
#  still ANDed, so a token naming a tenant the caller may not see grants nothing. The
#  || [Tenant ID] = -1 sentinel escape is preserved exactly.
#
#  Expression-only: no table, column or partition is touched, which is what keeps it inside
#  what the service principal may do. Run Scripts/Check_RLS_Expression.ps1 afterwards.
#
#  Creds: Scripts/fabric_creds.local.ps1 or FABRIC_SP_*.  -WhatIf to preview.
# ---------------------------------------------------------------------------
param(
    [switch]$WhatIf,
    # ==> THE SERVICE PRINCIPAL CAN READ THE MODEL BUT NOT ALTER IT. <== Any SaveChanges, even
    # an expression-only one, is refused with "in addition to Write permissions on the model,
    # make sure you also have at least Use permissions on all data connections". Rather than
    # widen a service principal's standing rights to land one change, connect as the signed-in
    # user with a delegated token -- the same pattern the prod warehouse deploys use. Reading
    # (Check_RLS_Expression.ps1) still works fine as the SP.
    [switch]$AsMe,
    [string]$WsName = $(if ($env:PBI_WORKSPACE_NAME) { $env:PBI_WORKSPACE_NAME } else { 'DEV - DM Dentally' }),
    [string]$DsName = $(if ($env:PBI_DATASET_NAME)   { $env:PBI_DATASET_NAME }   else { 'PBI Dentally' }),
    [string]$RlsRole = 'RLS',
    [string]$TenantCol = 'Tenant ID'
)

$ErrorActionPreference = 'Stop'

$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }
if (-not $AsMe -and -not ($env:FABRIC_SP_TENANT -and $env:FABRIC_SP_CLIENT_ID -and $env:FABRIC_SP_CLIENT_SECRET)) {
    Write-Host 'Missing FABRIC_SP_* credentials (or pass -AsMe).' -ForegroundColor Red; exit 2
}

$modBase = (Get-Module -ListAvailable SqlServer | Sort-Object Version -Descending |
            Select-Object -First 1).ModuleBase
if (-not $modBase) { Write-Host 'SqlServer PowerShell module not found.' -ForegroundColor Red; exit 2 }
foreach ($dll in @('Microsoft.AnalysisServices.Core.dll', 'Microsoft.AnalysisServices.Tabular.dll')) {
    $path = Get-ChildItem $modBase -Recurse -Filter $dll -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    if (-not $path) { Write-Host "$dll not found under $modBase" -ForegroundColor Red; exit 2 }
    Add-Type -Path $path
}

$userToken = $null
if ($AsMe) {
    # A delegated token goes on Server.AccessToken, NOT in the connection string -- the
    # Password= form is for a service principal secret and fails with "Authentication failed
    # for all authenticators".
    $userToken = (az account get-access-token --resource https://analysis.windows.net/powerbi/api `
                      --query accessToken -o tsv)
    if (-not $userToken) { Write-Host 'az token acquisition failed.' -ForegroundColor Red; exit 2 }
    $connStr = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$WsName;Initial Catalog=$DsName;"
} else {
    $connStr = "Data Source=powerbi://api.powerbi.com/v1.0/myorg/$WsName;Initial Catalog=$DsName;" +
               "User ID=app:$($env:FABRIC_SP_CLIENT_ID)@$($env:FABRIC_SP_TENANT);Password=$($env:FABRIC_SP_CLIENT_SECRET);"
}
$srv = New-Object Microsoft.AnalysisServices.Tabular.Server
if ($userToken) {
    $srv.AccessToken = New-Object Microsoft.AnalysisServices.AccessToken(
        $userToken, [DateTime]::UtcNow.AddMinutes(55))
}
try { $srv.Connect($connStr) }
catch { Write-Host "XMLA connection failed: $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

$db = $srv.Databases.GetByName($DsName)
$model = $db.Model
Write-Host "Connected to '$DsName' in '$WsName'." -ForegroundColor Green

$role = $model.Roles | Where-Object { $_.Name -eq $RlsRole } | Select-Object -First 1
if (-not $role) { Write-Host "No role '$RlsRole'." -ForegroundColor Red; $srv.Disconnect(); exit 2 }

$ANCHOR = 'Application Users'

# ---- the rule --------------------------------------------------------------
$newFilter = @"
VAR _cd = CUSTOMDATA()
RETURN
(
    [$TenantCol] IN
        SELECTCOLUMNS(
            FILTER('$ANCHOR', '$ANCHOR'[User UPN] = USERPRINCIPALNAME()),
            "$TenantCol", '$ANCHOR'[$TenantCol])
    && ( ISBLANK( _cd ) || LEN( _cd ) = 0 ||
         PATHCONTAINS( SUBSTITUTE( _cd, ",", "|" ), FORMAT( [$TenantCol], "0" ) ) )
)
|| [$TenantCol] = -1
"@

# Tenant-bearing = has the tenant column. The anchor table keeps its own UPN-only rule: it is
# what the rule READS, and a copy cut to the current scope could not answer what that scope
# contains.
$changed = 0; $skipped = @()
foreach ($t in $model.Tables) {
    if (-not ($t.Columns | Where-Object { $_.Name -eq $TenantCol })) { continue }
    if ($t.Name -eq $ANCHOR) { $skipped += "$($t.Name) (anchor)"; continue }

    $want = $newFilter

    $tp = $role.TablePermissions | Where-Object { $_.Name -eq $t.Name } | Select-Object -First 1
    if (-not $tp) {
        Write-Host "  + new permission on '$($t.Name)'" -ForegroundColor Yellow
        if (-not $WhatIf) {
            $tp = New-Object Microsoft.AnalysisServices.Tabular.TablePermission
            $tp.Table = $t
            $tp.FilterExpression = $want
            $role.TablePermissions.Add($tp)
        }
        $changed++
        continue
    }
    if ($tp.FilterExpression.Trim() -eq $want.Trim()) { continue }
    if (-not $WhatIf) { $tp.FilterExpression = $want }
    $changed++
}

Write-Host ""
Write-Host "tables to update : $changed"
foreach ($s in $skipped) { Write-Host "  left alone     : $s" -ForegroundColor DarkGray }

if ($WhatIf) {
    Write-Host "`n-WhatIf: nothing saved. New rule:`n$newFilter" -ForegroundColor Yellow
    $srv.Disconnect(); exit 0
}

Write-Host "`nsaving..." -ForegroundColor Cyan
$model.SaveChanges() | Out-Null

Write-Host "done." -ForegroundColor Green
$srv.Disconnect()
