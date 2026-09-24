# ---------------------------------------------------------------------------
# Check_Vendor_Data_Isolation.ps1  --  affiliate commission must never reach a customer
# ---------------------------------------------------------------------------
# Affiliate commission is VENDOR money: what we pay a referral partner for introducing a
# practice. It is not that practice's data and it is not the affiliate's view of other
# practices. It lives in Billing.vw_Affiliate_Commission / Billing.vw_Affiliate_Payout and in
# its own standalone semantic model, shared with nobody.
#
# THE RULE: it must NEVER appear in the PBI presentation schema, and NEVER in the 'PBI Dentally'
# semantic model -- not now, not later, not "temporarily". A practice owner seeing what an
# introducer earns from them, or an affiliate seeing a practice they did not introduce, is a
# breach of confidence that no feature justifies.
#
# WHY A SCRIPT AND NOT A COMMENT. Two things make this easy to get wrong by accident rather than
# by decision:
#   * PBI.* views are GENERATED. Meta.usp_Create_Gold_Views sweeps the Gold schema into the PBI
#     schema automatically. Billing is out of its reach TODAY (it filters s.name = 'Gold'), so
#     the protection is structural -- but moving one of these views into Gold, or widening that
#     filter, would publish vendor money into the customer model with nobody deciding to.
#   * The customer model is RLS-scoped on [Tenant ID], and these views HAVE a Tenant_ID. So
#     Check_RLS_Coverage.ps1 would happily pass them once imported: they would look correctly
#     secured while being the wrong data in the wrong place entirely. RLS is not the control
#     here; absence is.
#
# Checks the WAREHOUSE in both environments (the realistic accident: someone adds a PBI view),
# and the dev semantic model. The prod model cannot be reached -- the Test Runner SP is dev-only
# -- so prod model isolation rests on the deployment pipeline promoting a clean dev model.
#
# Usage:  .\Scripts\Check_Vendor_Data_Isolation.ps1
# Exit:   0 = isolated; 1 = vendor data has leaked into a customer surface; 2 = config error.
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

$credFile = Join-Path $PSScriptRoot 'fabric_creds.local.ps1'
if (Test-Path $credFile) { . $credFile }

$endpoints = @{
    dev  = 'emeh72n2ntdufpj4q665b2lzx4-4i26eirspjiujnltrvplquzkem.datawarehouse.fabric.microsoft.com'
    prod = 'emeh72n2ntdufpj4q665b2lzx4-eljzajgm5cpe5i64szgon7sej4.datawarehouse.fabric.microsoft.com'
}

# Patterns that identify vendor-money data wherever it turns up. Deliberately broad: it is far
# better to fail on an innocent column called "Commission Rate" and have someone justify it than
# to miss "Affiliate Payout" because the check was written to match exactly two view names.
$forbidden = "'%ffiliate%', '%ommission%', '%ayout%', '%ntroducer%'"

$sql = @"
SELECT TABLE_SCHEMA + '.' + TABLE_NAME + ' [' + COLUMN_NAME + ']' AS Leak
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PBI'
  AND (COLUMN_NAME LIKE '%ffiliate%' OR COLUMN_NAME LIKE '%ommission%'
       OR COLUMN_NAME LIKE '%ayout%'  OR COLUMN_NAME LIKE '%ntroducer%')
UNION ALL
SELECT TABLE_SCHEMA + '.' + TABLE_NAME + ' [object name]'
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PBI'
  AND (TABLE_NAME LIKE '%ffiliate%' OR TABLE_NAME LIKE '%ommission%'
       OR TABLE_NAME LIKE '%ayout%'  OR TABLE_NAME LIKE '%ntroducer%');
"@

function Get-Token {
    $t = az account get-access-token --resource https://database.windows.net --query accessToken -o tsv 2>$null
    if (-not $t) { Write-Host 'Could not get a database token (az login?).' -ForegroundColor Red; exit 2 }
    return $t.Trim()
}

Add-Type -AssemblyName System.Data
$token = Get-Token
$leaks = @()

foreach ($env in 'dev', 'prod') {
    $cs = "Server=tcp:$($endpoints[$env]),1433;Database=WH_Dentally;Encrypt=True;TrustServerCertificate=False;Connect Timeout=30;"
    $conn = New-Object System.Data.SqlClient.SqlConnection $cs
    $conn.AccessToken = $token
    try { $conn.Open() }
    catch { Write-Host "$env : connection failed -- $($_.Exception.Message)" -ForegroundColor Red; exit 2 }

    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql
    $rdr = $cmd.ExecuteReader()
    $found = @()
    while ($rdr.Read()) { $found += $rdr.GetString(0) }
    $rdr.Close(); $conn.Close()

    if ($found.Count -eq 0) {
        Write-Host ("{0,-5} warehouse PBI schema clean" -f $env) -ForegroundColor Green
    } else {
        Write-Host ("{0,-5} VENDOR DATA IN THE PBI SCHEMA:" -f $env) -ForegroundColor Red
        $found | ForEach-Object { Write-Host "        $_" -ForegroundColor Red }
        $leaks += $found | ForEach-Object { "$env : $_" }
    }
}

# ── the dev semantic model ────────────────────────────────────────────────────
$Tenant   = $env:FABRIC_SP_TENANT
$ClientId = $env:FABRIC_SP_CLIENT_ID
$Secret   = $env:FABRIC_SP_CLIENT_SECRET

if ($Tenant -and $ClientId -and $Secret -and (Get-Module -ListAvailable SqlServer)) {
    try {
        Import-Module SqlServer -ErrorAction Stop
        $sec  = ConvertTo-SecureString $Secret -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($ClientId, $sec)
        $dax  = 'EVALUATE SELECTCOLUMNS(FILTER(INFO.TABLES(), SEARCH("ffiliate", [Name], 1, 0) > 0 || SEARCH("ommission", [Name], 1, 0) > 0 || SEARCH("ayout", [Name], 1, 0) > 0), "a", [Name])'
        $raw = Invoke-ASCmd -Server 'powerbi://api.powerbi.com/v1.0/myorg/DEV - DM Dentally' `
                            -Database 'PBI Dentally' -Query $dax `
                            -ServicePrincipal -ApplicationId $ClientId -TenantId $Tenant `
                            -Credential $cred -ErrorAction Stop
        $rows = Select-Xml -Xml ([xml]$raw) -XPath '//r:row' `
                           -Namespace @{ r = 'urn:schemas-microsoft-com:xml-analysis:rowset' }
        if ($rows.Count -eq 0) {
            Write-Host "dev   'PBI Dentally' model carries no vendor tables" -ForegroundColor Green
        } else {
            Write-Host "dev   VENDOR TABLES IN THE CUSTOMER MODEL:" -ForegroundColor Red
            foreach ($r in $rows) { Write-Host "        $($r.Node.C0)" -ForegroundColor Red; $leaks += "dev model : $($r.Node.C0)" }
        }
    } catch {
        Write-Host "dev   model check skipped -- $($_.Exception.Message.Split([char]10)[0])" -ForegroundColor Yellow
    }
} else {
    Write-Host 'dev   model check skipped (no FABRIC_SP_* creds, or the SqlServer module is absent)' -ForegroundColor Yellow
}

Write-Host ''
if ($leaks.Count -eq 0) {
    Write-Host 'PASS - affiliate commission is not on any customer surface.' -ForegroundColor Green
    exit 0
}
Write-Host "FAIL - $($leaks.Count) leak(s). Affiliate commission is vendor money and must not be" -ForegroundColor Red
Write-Host '       reachable by a practice or by another affiliate. Remove it from the customer' -ForegroundColor Red
Write-Host '       surface rather than adding RLS to it -- absence is the control, not RLS.' -ForegroundColor Red
exit 1
