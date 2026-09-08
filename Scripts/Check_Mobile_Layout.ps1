# ---------------------------------------------------------------------------
# Check_Mobile_Layout.ps1  --  phone-layout guard for the PBIP reports
# ---------------------------------------------------------------------------
# In PBIR every visual carries its phone placement in its own
#   definition/pages/<page>/visuals/<id>/mobile.json
# A visual with NO mobile.json is simply absent from the phone canvas. It fails
# silently: nothing warns you in Desktop, and the report still publishes.
#
# That is harmless for decoration and fatal for navigation, because the reports
# navigate by BOOKMARK. A bookmark's show/hide state applies on phone too, so a
# bookmark that reveals a visual with no phone placement produces a blank
# screen -- the switcher appears to do nothing. This script encodes that rule.
#
# Checks (per report, per page):
#   1. NAVIGATOR   - a bookmarkNavigator/pageNavigator with no mobile.json:
#                    the view switcher does not exist on the phone.
#   2. DEAD STATE  - a bookmark that SHOWS a visual which has no mobile.json:
#                    selecting that bookmark on a phone shows nothing.
#   3. LOST ACTION - an actionButton with no mobile.json: drillthrough/back/
#                    page navigation is unreachable on the phone.
#   4. ENCODING    - any .json in the report definition carrying a UTF-8 BOM or
#                    failing to parse. PBIR requires UTF-8 WITHOUT a BOM; a BOM
#                    makes Power BI Desktop refuse to open the report outright.
#                    NB this differs from the SQL files, which are UTF-16 LE
#                    WITH BOM (see CLAUDE.md) -- do not confuse the two.
#                    PowerShell 5.1's `Out-File -Encoding utf8` ALWAYS writes a
#                    BOM; use [System.IO.File]::WriteAllText with
#                    UTF8Encoding($false) instead.
#   5. COVERAGE    - reported for information only, never fails the run.
#
# Reports under -Reports (default: the nine embedded by the web app). The
# Template scaffold and the Day_Book2 backup are excluded by default.
#
# Exit: 0 = clean; 1 = one or more failures; 2 = config error.
# ---------------------------------------------------------------------------

[CmdletBinding()]
param(
    [string]   $PbiRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'PBI'),
    [string[]] $Reports,
    [string[]] $Exclude = @('Template', 'Day_Book2'),
    [switch]   $Detailed
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $PbiRoot)) {
    Write-Host "PBI root not found: $PbiRoot" -ForegroundColor Red
    exit 2
}

$failures = @()
$info     = @()

# Visuals that are deliberately absent from the phone layout (PBI/mobile-exempt.json):
#   { "<Report>": { "<visualId>": "why it is desktop-only" } }
# e.g. the wide KPI ribbons, which phone reaches via the KPI button + KPIs page.
$exempt = @{}
$exemptFile = Join-Path $PbiRoot 'mobile-exempt.json'
if (Test-Path $exemptFile) {
    $ex = Get-Content $exemptFile -Raw | ConvertFrom-Json
    foreach ($r in $ex.PSObject.Properties) {
        $set = @{}
        foreach ($v in $r.Value.PSObject.Properties) { $set[$v.Name] = $v.Value }
        $exempt[$r.Name] = $set
    }
}
function Test-Exempt($report, $visualId) {
    return ($exempt.ContainsKey($report) -and $exempt[$report].ContainsKey($visualId))
}
$exemptHits = 0

function Add-Failure($rule, $report, $page, $detail) {
    $script:failures += [pscustomobject]@{ Rule = $rule; Report = $report; Page = $page; Detail = $detail }
}

$reportDirs = Get-ChildItem $PbiRoot -Directory -Filter '*.Report' | Where-Object {
    $n = $_.Name -replace '\.Report$', ''
    ($Exclude -notcontains $n) -and (-not $Reports -or $Reports -contains $n)
}

if (-not $reportDirs) { Write-Host "No reports matched." -ForegroundColor Red; exit 2 }

foreach ($rep in $reportDirs) {
    $name = $rep.Name -replace '\.Report$', ''
    $def  = Join-Path $rep.FullName 'definition'
    $pagesRoot = Join-Path $def 'pages'
    if (-not (Test-Path $pagesRoot)) { continue }

    # ---- index every visual: id -> type, page, phone placement -------------
    $visual = @{}
    foreach ($pageDir in Get-ChildItem $pagesRoot -Directory) {
        $pj = Join-Path $pageDir.FullName 'page.json'
        if (-not (Test-Path $pj)) { continue }
        $pageName = (Get-Content $pj -Raw | ConvertFrom-Json).displayName
        foreach ($vd in Get-ChildItem (Join-Path $pageDir.FullName 'visuals') -Directory -ErrorAction SilentlyContinue) {
            $vj = Join-Path $vd.FullName 'visual.json'
            if (-not (Test-Path $vj)) { continue }
            $v = Get-Content $vj -Raw | ConvertFrom-Json
            $visual[$vd.Name] = [pscustomobject]@{
                Type     = $v.visual.visualType
                Page     = $pageName
                HasPhone = Test-Path (Join-Path $vd.FullName 'mobile.json')
            }
        }
    }

    # ---- 1 + 3: navigators and action buttons -----------------------------
    foreach ($v in $visual.GetEnumerator()) {
        $t = $v.Value.Type
        if ($v.Value.HasPhone) { continue }
        if (Test-Exempt $name $v.Key) { $script:exemptHits++; continue }
        if ($t -in @('bookmarkNavigator', 'pageNavigator')) {
            Add-Failure 'NAVIGATOR' $name $v.Value.Page "$t has no mobile.json - no view switcher on phone"
        } elseif ($t -eq 'actionButton') {
            Add-Failure 'LOST ACTION' $name $v.Value.Page "actionButton ($($v.Key.Substring(0,8))) has no mobile.json"
        }
    }

    # ---- 2: bookmarks revealing visuals that are not on the phone ---------
    $bmDir = Join-Path $def 'bookmarks'
    if (Test-Path $bmDir) {
        foreach ($bf in Get-ChildItem $bmDir -Filter '*.bookmark.json') {
            $b = Get-Content $bf.FullName -Raw | ConvertFrom-Json
            $secs = $b.explorationState.sections
            if (-not $secs) { continue }
            foreach ($sec in $secs.PSObject.Properties) {
                $vcs = $sec.Value.visualContainers
                if (-not $vcs) { continue }
                $orphans = @()
                foreach ($vc in $vcs.PSObject.Properties) {
                    $mode = $null
                    try { $mode = $vc.Value.singleVisual.display.mode } catch {}
                    if ($mode -eq 'hidden') { continue }          # hidden: absence is correct
                    if (Test-Exempt $name $vc.Name) { $script:exemptHits++; continue }
                    $inf = $visual[$vc.Name]
                    if ($inf -and -not $inf.HasPhone) { $orphans += $inf.Type }
                }
                if ($orphans.Count) {
                    $pageName = 'unknown'
                    $anyId = ($vcs.PSObject.Properties | Select-Object -First 1).Name
                    if ($visual[$anyId]) { $pageName = $visual[$anyId].Page }
                    $summary = ($orphans | Group-Object | ForEach-Object { "$($_.Count)x $($_.Name)" }) -join ', '
                    Add-Failure 'DEAD STATE' $name $pageName "bookmark '$($b.displayName)' shows $($orphans.Count) visual(s) absent from phone: $summary"
                }
            }
        }
    }

    # ---- 4: encoding -- PBIR needs UTF-8 with NO BOM ----------------------
    foreach ($jf in Get-ChildItem $def -Recurse -File -Filter '*.json') {
        $bytes = [System.IO.File]::ReadAllBytes($jf.FullName)
        $rel   = $jf.FullName.Replace($rep.FullName, '').TrimStart('\')
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Add-Failure 'ENCODING' $name '-' "$rel has a UTF-8 BOM - Power BI Desktop will refuse to open this report"
            continue
        }
        try { Get-Content $jf.FullName -Raw | ConvertFrom-Json | Out-Null }
        catch { Add-Failure 'ENCODING' $name '-' "$rel is not valid JSON: $($_.Exception.Message)" }
    }

    # ---- 5: coverage, informational ---------------------------------------
    foreach ($grp in ($visual.Values | Group-Object Page)) {
        $tot = $grp.Count
        $on  = @($grp.Group | Where-Object HasPhone).Count
        $info += [pscustomobject]@{
            Report = $name; Page = $grp.Name; Visuals = $tot; OnPhone = $on
            Coverage = "{0,3:N0}%" -f ($on / $tot * 100)
        }
    }
}

# ---------------------------------------------------------------- reporting
Write-Host ""
Write-Host "=== Mobile layout coverage ===" -ForegroundColor Cyan
$info | Sort-Object Report, Page | Format-Table Report, Page, Visuals, OnPhone, Coverage -AutoSize

if ($exemptHits) {
    Write-Host "$exemptHits deliberate desktop-only visual(s) skipped (see PBI/mobile-exempt.json)." -ForegroundColor DarkGray
}

if ($failures.Count -eq 0) {
    Write-Host "PASS - every navigator, action button and bookmark state is present on the phone layout." -ForegroundColor Green
    exit 0
}

Write-Host "=== FAILURES ($($failures.Count)) ===" -ForegroundColor Red
foreach ($rule in @('ENCODING', 'NAVIGATOR', 'DEAD STATE', 'LOST ACTION')) {
    $set = $failures | Where-Object Rule -eq $rule
    if (-not $set) { continue }
    Write-Host ""
    Write-Host "  $rule ($($set.Count))" -ForegroundColor Yellow
    if ($Detailed) { $set | Format-Table Report, Page, Detail -AutoSize -Wrap }
    else { $set | Select-Object Report, Page, Detail | Format-Table -AutoSize }
}
Write-Host ""
Write-Host "Summary by report:" -ForegroundColor Yellow
$failures | Group-Object Report | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
exit 1
