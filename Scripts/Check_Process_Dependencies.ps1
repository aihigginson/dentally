<#
.SYNOPSIS
    Static guard: a Gold load that READS another Gold base-fact table must have a
    dependency edge ordering it after that fact (i.e. be GOLD_AGG).
.DESCRIPTION
    The dependency generator (Generate_Process_Dependencies.ps1) only emits
    layer-transition edges and has NO fact->fact rule on purpose (a generic one
    phantom-cycles). So a load that reads another Gold FACT but is categorised
    GOLD_FACT/GOLD_DIM gets only Dim->Fact edges, lands in the same build wave as
    the fact it reads, and can run a wave late (reading last night's data).

    The fix for "derived load reads a base fact" is to categorise it GOLD_AGG
    (terminal): the generator's Gold->Agg rule then adds an edge from every fact
    it reads, so Orchestrate_Build orders it AFTER those sources.

    This guard re-derives, statically from the repo, every Gold load that reads a
    base-fact table (FROM/JOIN, comments stripped, excluding tables it writes
    itself) and fails if the matching Prev->Next edge is missing from
    Audit.Process_Dependency.Data.sql. It needs no warehouse connection.

    Exit 0 = clean. Exit 1 = at least one missing-edge violation.
.NOTES
    A base fact = a Gold table written by a GOLD_FACT_* job. Reading a Dim is fine
    (Dim->Fact is level 4). Reading an AGG table is not flagged (aggs are terminal).
#>

$ErrorActionPreference = 'Stop'
$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

# ---------------------------------------------------------------------------
# 1. Process_Config -> name<->codes
# ---------------------------------------------------------------------------
$pcContent = Get-Content (Join-Path $FabricDir 'Audit.Process_Config.Data.sql') -Raw -Encoding UTF8
$pcMap = @{}   # Process_Name -> List[Process_Code]
$valPattern = [regex]"VALUES\s+\('([^']+)',\s*'([^']+)'"
foreach ($m in $valPattern.Matches($pcContent)) {
    $code = $m.Groups[1].Value
    $name = $m.Groups[2].Value
    if (-not $pcMap.ContainsKey($name)) { $pcMap[$name] = [System.Collections.Generic.List[string]]::new() }
    $pcMap[$name].Add($code)
}

# ---------------------------------------------------------------------------
# 2. Process_Dependency -> set of "PREV|NEXT" edges
# ---------------------------------------------------------------------------
$depContent = Get-Content (Join-Path $FabricDir 'Audit.Process_Dependency.Data.sql') -Raw -Encoding UTF8
$edges = @{}
foreach ($m in ([regex]"VALUES\s+\('([^']+)',\s*'([^']+)'").Matches($depContent)) {
    $edges["$($m.Groups[1].Value)|$($m.Groups[2].Value)"] = $true
}

# ---------------------------------------------------------------------------
# 3. Helpers (mirror Generate_Process_Dependencies.ps1, plus comment stripping)
# ---------------------------------------------------------------------------
function Remove-Brackets { param([string]$t) $t -replace '\[', '' -replace '\]', '' }

function Strip-Comments {
    param([string]$t)
    $t = [regex]::Replace($t, '/\*.*?\*/', ' ', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $t = [regex]::Replace($t, '--[^\r\n]*', ' ')
    $t
}

# Tables a SP writes: MERGE INTO / INSERT INTO / MERGE  Gold.X
function Get-GoldWrites {
    param([string]$t)
    $c = Remove-Brackets $t
    ([regex]"(?i)(?:MERGE\s+INTO|INSERT\s+INTO|MERGE)\s+Gold\.(\w+)").Matches($c) |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
}

# Tables a SP genuinely reads: FROM / JOIN Gold.X (comments removed)
function Get-GoldReads {
    param([string]$t)
    $c = Strip-Comments (Remove-Brackets $t)
    ([regex]"(?i)(?:FROM|JOIN)\s+Gold\.(\w+)").Matches($c) |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
}

# ---------------------------------------------------------------------------
# 4. Load Gold SPs
# ---------------------------------------------------------------------------
$gold = @{}
foreach ($f in Get-ChildItem (Join-Path $FabricDir 'Gold.usp_*.StoredProcedure.sql')) {
    $gold[($f.Name -replace '\.StoredProcedure\.sql$', '')] = Get-Content $f.FullName -Raw -Encoding UTF8
}

# ---------------------------------------------------------------------------
# 5. Base-fact table -> writer GOLD_FACT_* code(s)
# ---------------------------------------------------------------------------
$factWriters = @{}   # table -> List[code]
foreach ($name in $gold.Keys) {
    if (-not $pcMap.ContainsKey($name)) { continue }
    $factCodes = @($pcMap[$name] | Where-Object { $_ -like 'GOLD_FACT_*' })
    if ($factCodes.Count -eq 0) { continue }
    foreach ($t in (Get-GoldWrites $gold[$name])) {
        if (-not $factWriters.ContainsKey($t)) { $factWriters[$t] = [System.Collections.Generic.List[string]]::new() }
        foreach ($c in $factCodes) { if (-not $factWriters[$t].Contains($c)) { $factWriters[$t].Add($c) } }
    }
}

# ---------------------------------------------------------------------------
# 6. For every Gold load that reads a base fact, require the ordering edge
# ---------------------------------------------------------------------------
$violations = [System.Collections.Generic.List[string]]::new()
$checked = 0
foreach ($name in ($gold.Keys | Sort-Object)) {
    if (-not $pcMap.ContainsKey($name)) { continue }
    $codes  = $pcMap[$name]
    $writes = Get-GoldWrites $gold[$name]
    $reads  = @(Get-GoldReads $gold[$name] | Where-Object { $writes -notcontains $_ })
    foreach ($t in $reads) {
        if (-not $factWriters.ContainsKey($t)) { continue }                       # not a base fact -> fine
        $writerCodes = @($factWriters[$t] | Where-Object { $codes -notcontains $_ })  # written by another job
        if ($writerCodes.Count -eq 0) { continue }
        $checked++
        foreach ($rc in $codes) {
            foreach ($wc in $writerCodes) {
                if (-not $edges.ContainsKey("$wc|$rc")) {
                    $violations.Add("$name [$rc] reads Gold.$t (base fact, written by $wc) -- missing ordering edge $wc -> $rc")
                }
            }
        }
    }
}

Write-Host "Process dependency guard: $($gold.Count) Gold SPs, $($factWriters.Count) base-fact tables, $checked fact-read relationship(s) checked."

if ($violations.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILED ($($violations.Count) issue(s)):" -ForegroundColor Red
    $violations | Sort-Object -Unique | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "A Gold load that reads another Gold FACT should be GOLD_AGG (terminal), so the"
    Write-Host "build orders it after that fact. To fix each:"
    Write-Host "  1) Audit.Process_Config: change the load's code GOLD_FACT_X -> GOLD_AGG_X (category GOLD_AGG)"
    Write-Host "  2) Audit.usp_Load_All: that step's @Step -> 'Agg_X' (so 'GOLD_'+UPPER(@Step) yields the AGG code)"
    Write-Host "  3) re-run Scripts\Generate_Process_Dependencies.ps1 to emit the Gold->Agg edge(s)"
    Write-Host "  (If the load is NOT terminal -- another Gold load reads it -- that's a deeper design issue.)"
    exit 1
}

Write-Host "PASSED: every Gold load that reads a base fact has an ordering edge (or is GOLD_AGG)." -ForegroundColor Green
exit 0
