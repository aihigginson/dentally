<#
.SYNOPSIS
    Generates Audit.Process_Dependency.Data.sql by scanning SP definition files.
.DESCRIPTION
    Reads Bronze/Silver/Gold stored procedure files, extracts table references
    via regex, then emits DELETE + INSERT statements to
    Audit.Process_Dependency.Data.sql.

    Run this script after adding or changing any SP, then deploy the output
    file alongside Audit.Process_Config.Data.sql.

    Dependency logic:
      Bronze SP writes  Bronze.X  AND  Silver SP mentions Bronze.X  => Bronze->Silver (level 1)
      Silver SP writes  Silver.X  AND  Gold SP   mentions Silver.X  => Silver->Gold   (level 2)
      Gold F/D SP writes Gold.X   AND  Gold Agg  mentions Gold.X   => Gold->Agg      (level 3)

    Only SPs registered in Audit.Process_Config.Data.sql are included.
.EXAMPLE
    .\Generate_Process_Dependencies.ps1
#>

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# 1. Parse Process_Config.Data.sql -> process_name -> [process_code, ...]
# ---------------------------------------------------------------------------
$pcFile    = Join-Path $ScriptDir 'Audit.Process_Config.Data.sql'
$pcContent = Get-Content $pcFile -Raw -Encoding UTF8

$pcMap = @{}   # key = Process_Name (e.g. 'Bronze.usp_Load_Practitioners')
               # val = List of Process_Code strings

$valPattern = [regex]"VALUES\s+\('([^']+)',\s*'([^']+)'"
foreach ($m in $valPattern.Matches($pcContent)) {
    $code = $m.Groups[1].Value
    $name = $m.Groups[2].Value
    if (-not $pcMap.ContainsKey($name)) {
        $pcMap[$name] = [System.Collections.Generic.List[string]]::new()
    }
    $pcMap[$name].Add($code)
}

Write-Host "Process_Config: $($pcMap.Count) distinct SP names loaded"

# ---------------------------------------------------------------------------
# 2. Helper functions
# ---------------------------------------------------------------------------

# Strip square brackets so [Silver].[Patients] matches the same as Silver.Patients
function Remove-Brackets { param([string]$text); $text -replace '\[', '' -replace '\]', '' }

# Tables a SP writes to: MERGE INTO Schema.X  |  MERGE Schema.X  |  INSERT INTO Schema.X
function Get-WriteTargets {
    param([string]$text, [string]$schema)
    $clean = Remove-Brackets $text
    $pat   = [regex]"(?i)(?:MERGE\s+INTO|INSERT\s+INTO|MERGE)\s+$schema\.(\w+)"
    ($pat.Matches($clean) | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
}

# Tables a SP mentions (any occurrence): used to detect reads
function Get-Mentions {
    param([string]$text, [string]$schema)
    $clean = Remove-Brackets $text
    $pat   = [regex]"(?i)\b$schema\.(\w+)\b"
    ($pat.Matches($clean) | ForEach-Object { $_.Groups[1].Value }) | Sort-Object -Unique
}

# Qualified SP name from file path: 'Bronze.usp_Load_Practitioners' etc.
function Get-QualifiedName {
    param([System.IO.FileInfo]$file)
    $file.Name -replace '\.StoredProcedure\.sql$', ''
}

# ---------------------------------------------------------------------------
# 3. Load SP files
# ---------------------------------------------------------------------------
$bronzeFiles = Get-ChildItem (Join-Path $ScriptDir 'Bronze.usp_*.StoredProcedure.sql')
$silverFiles = Get-ChildItem (Join-Path $ScriptDir 'Silver.usp_*.StoredProcedure.sql')
$goldFiles   = Get-ChildItem (Join-Path $ScriptDir 'Gold.usp_*.StoredProcedure.sql')

$bronzeSps = @{}
foreach ($f in $bronzeFiles) {
    $bronzeSps[(Get-QualifiedName $f)] = Get-Content $f.FullName -Raw -Encoding UTF8
}

$silverSps = @{}
foreach ($f in $silverFiles) {
    $silverSps[(Get-QualifiedName $f)] = Get-Content $f.FullName -Raw -Encoding UTF8
}

$goldSps = @{}
foreach ($f in $goldFiles) {
    $goldSps[(Get-QualifiedName $f)] = Get-Content $f.FullName -Raw -Encoding UTF8
}

Write-Host "Loaded: $($bronzeSps.Count) Bronze, $($silverSps.Count) Silver, $($goldSps.Count) Gold SPs"

# ---------------------------------------------------------------------------
# 4. Build dependency list
# ---------------------------------------------------------------------------
$deps = [System.Collections.Generic.List[string]]::new()   # "PREV|NEXT|LEVEL"

# -- Level 1: Bronze SP writes Bronze.X  &  Silver SP mentions Bronze.X ------
foreach ($bName in $bronzeSps.Keys) {
    if (-not $pcMap.ContainsKey($bName)) { continue }
    $bCodes    = $pcMap[$bName]
    $bWrites   = Get-WriteTargets $bronzeSps[$bName] 'Bronze'
    if ($bWrites.Count -eq 0) { continue }

    foreach ($sName in $silverSps.Keys) {
        if (-not $pcMap.ContainsKey($sName)) { continue }
        $sMentions = Get-Mentions $silverSps[$sName] 'Bronze'
        $shared    = $bWrites | Where-Object { $sMentions -contains $_ }
        if ($shared.Count -eq 0) { continue }

        $sCodes = $pcMap[$sName]
        foreach ($bc in $bCodes) {
            foreach ($sc in $sCodes) {
                $deps.Add("$bc|$sc|1")
            }
        }
    }
}

# -- Level 2: Silver SP writes Silver.X  &  another Silver SP mentions Silver.X
foreach ($s1Name in $silverSps.Keys) {
    if (-not $pcMap.ContainsKey($s1Name)) { continue }
    $s1Codes  = $pcMap[$s1Name]
    $s1Writes = Get-WriteTargets $silverSps[$s1Name] 'Silver'
    if ($s1Writes.Count -eq 0) { continue }

    foreach ($s2Name in $silverSps.Keys) {
        if ($s2Name -eq $s1Name) { continue }
        if (-not $pcMap.ContainsKey($s2Name)) { continue }
        $s2Mentions = Get-Mentions $silverSps[$s2Name] 'Silver'
        $shared     = $s1Writes | Where-Object { $s2Mentions -contains $_ }
        if ($shared.Count -eq 0) { continue }

        $s2Codes = $pcMap[$s2Name]
        foreach ($s1c in $s1Codes) {
            foreach ($s2c in $s2Codes) {
                $deps.Add("$s1c|$s2c|2")
            }
        }
    }
}

# -- Level 3: Silver SP writes Silver.X  &  Gold SP mentions Silver.X ---------
foreach ($sName in $silverSps.Keys) {
    if (-not $pcMap.ContainsKey($sName)) { continue }
    $sCodes  = $pcMap[$sName]
    $sWrites = Get-WriteTargets $silverSps[$sName] 'Silver'
    if ($sWrites.Count -eq 0) { continue }

    foreach ($gName in $goldSps.Keys) {
        if (-not $pcMap.ContainsKey($gName)) { continue }
        $gMentions = Get-Mentions $goldSps[$gName] 'Silver'
        $shared    = $sWrites | Where-Object { $gMentions -contains $_ }
        if ($shared.Count -eq 0) { continue }

        $gCodes = $pcMap[$gName]
        foreach ($sc in $sCodes) {
            foreach ($gc in $gCodes) {
                $deps.Add("$sc|$gc|3")
            }
        }
    }
}

# -- Level 4: Gold Dim SP writes Gold.Dim_X  &  Gold Fact SP mentions Gold.Dim_X
foreach ($gdName in $goldSps.Keys) {
    if (-not $pcMap.ContainsKey($gdName)) { continue }
    $gdCodes = @($pcMap[$gdName] | Where-Object { $_ -like 'GOLD_DIM_*' })
    if ($gdCodes.Count -eq 0) { continue }

    $gdWrites = Get-WriteTargets $goldSps[$gdName] 'Gold'
    if ($gdWrites.Count -eq 0) { continue }

    foreach ($gfName in $goldSps.Keys) {
        if ($gfName -eq $gdName) { continue }
        if (-not $pcMap.ContainsKey($gfName)) { continue }
        $gfCodes = @($pcMap[$gfName] | Where-Object { $_ -like 'GOLD_FACT_*' })
        if ($gfCodes.Count -eq 0) { continue }

        $gfMentions = Get-Mentions $goldSps[$gfName] 'Gold'
        $shared     = $gdWrites | Where-Object { $gfMentions -contains $_ }
        if ($shared.Count -eq 0) { continue }

        foreach ($gdc in $gdCodes) {
            foreach ($gfc in $gfCodes) {
                $deps.Add("$gdc|$gfc|4")
            }
        }
    }
}

# -- Level 5: Gold Fact/Dim SP writes Gold.X  &  Gold Agg SP mentions Gold.X --
foreach ($gfName in $goldSps.Keys) {
    if (-not $pcMap.ContainsKey($gfName)) { continue }
    $gfCodes = @($pcMap[$gfName] | Where-Object { $_ -like 'GOLD_FACT_*' -or $_ -like 'GOLD_DIM_*' })
    if ($gfCodes.Count -eq 0) { continue }

    $gfWrites = Get-WriteTargets $goldSps[$gfName] 'Gold'
    if ($gfWrites.Count -eq 0) { continue }

    foreach ($gaName in $goldSps.Keys) {
        if ($gaName -eq $gfName) { continue }
        if (-not $pcMap.ContainsKey($gaName)) { continue }
        $gaCodes = @($pcMap[$gaName] | Where-Object { $_ -like 'GOLD_AGG_*' })
        if ($gaCodes.Count -eq 0) { continue }

        $gaMentions = Get-Mentions $goldSps[$gaName] 'Gold'
        $shared     = $gfWrites | Where-Object { $gaMentions -contains $_ }
        if ($shared.Count -eq 0) { continue }

        foreach ($gfc in $gfCodes) {
            foreach ($gac in $gaCodes) {
                $deps.Add("$gfc|$gac|5")
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Deduplicate and sort
# ---------------------------------------------------------------------------
$unique = $deps | Sort-Object | Select-Object -Unique

$l1 = @($unique | Where-Object { $_.EndsWith('|1') })
$l2 = @($unique | Where-Object { $_.EndsWith('|2') })
$l3 = @($unique | Where-Object { $_.EndsWith('|3') })
$l4 = @($unique | Where-Object { $_.EndsWith('|4') })
$l5 = @($unique | Where-Object { $_.EndsWith('|5') })

Write-Host "Dependencies found:"
Write-Host "  Bronze -> Silver   (1): $($l1.Count)"
Write-Host "  Silver -> Silver   (2): $($l2.Count)"
Write-Host "  Silver -> Gold     (3): $($l3.Count)"
Write-Host "  Gold Dim -> Fact   (4): $($l4.Count)"
Write-Host "  Gold -> Agg        (5): $($l5.Count)"
Write-Host "  Total                 : $($unique.Count)"

# ---------------------------------------------------------------------------
# 6. Write SQL output file (ASCII encoding)
# ---------------------------------------------------------------------------
$outFile = Join-Path $ScriptDir 'Audit.Process_Dependency.Data.sql'

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('-- =============================================================================')
$lines.Add('-- Audit.Process_Dependency -- seed data')
$lines.Add('-- Generated by Generate_Process_Dependencies.ps1')
$lines.Add('-- Do not edit manually -- re-run the script to regenerate.')
$lines.Add('-- =============================================================================')
$lines.Add('')
$lines.Add('DELETE FROM Audit.Process_Dependency;')
$lines.Add('GO')
$lines.Add('')

function Add-Section {
    param([string[]]$rows, [string]$label)
    if ($rows.Count -eq 0) { return }
    $lines.Add("-- $label")
    foreach ($row in $rows) {
        $parts = $row -split '\|'
        $prev  = $parts[0]; $next = $parts[1]; $lvl = $parts[2]
        $lines.Add("INSERT INTO Audit.Process_Dependency (Prev_Process_Code, Next_Process_Code, Dependency_Type, Dependency_Level, Is_Active) VALUES ('$prev', '$next', 'DATA', $lvl, 1);")
    }
    $lines.Add('')
}

Add-Section $l1 'Bronze -> Silver  (level 1)'
Add-Section $l2 'Silver -> Silver  (level 2)'
Add-Section $l3 'Silver -> Gold    (level 3)'
Add-Section $l4 'Gold Dim -> Fact  (level 4)'
Add-Section $l5 'Gold -> Agg       (level 5)'

[System.IO.File]::WriteAllLines($outFile, $lines, [System.Text.ASCIIEncoding]::new())

Write-Host "Written: $outFile"
