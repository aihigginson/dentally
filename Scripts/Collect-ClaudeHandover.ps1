<#
.SYNOPSIS
    One-shot collector: sweeps everything off an old PC that Claude Code (or you)
    would otherwise have to go back for. Writes into OneDrive so it syncs to the
    new machine on its own - no USB stick, no second trip.

.DESCRIPTION
    Run this ON THE OLD PC. It writes to:
        <OneDrive>\ClaudeHandover\<COMPUTERNAME>\

    Every section is best-effort: a failure is logged and skipped, never aborts the
    run. MANIFEST.md records what was collected, what was missing, and - importantly -
    what CANNOT be scripted and must be done by hand before the machine is wiped.

    DELIBERATELY NOT COPIED: SSH private keys, Azure CLI tokens, GitHub CLI tokens,
    Claude's auth token. Signing in again on the new machine takes seconds and is
    safer than copying credentials through cloud storage. The script REPORTS whether
    each exists so you know what to re-authenticate.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File "<path to this file>"
#>
[CmdletBinding()]
param(
    [string] $Destination,
    [int]    $MaxDownloadsMB = 250
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- destination
$od = $env:OneDrive
if (-not $od) { $od = $env:OneDriveConsumer }
if (-not $od) { $od = Join-Path $env:USERPROFILE 'OneDrive' }
if (-not (Test-Path $od)) {
    Write-Host "FATAL: no OneDrive folder found. Re-run with -Destination <path>." -ForegroundColor Red
    exit 1
}
if (-not $Destination) { $Destination = Join-Path $od "ClaudeHandover\$env:COMPUTERNAME" }
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

$script:log = @()
function Note($status, $what, $detail) {
    $script:log += [pscustomobject]@{ Status = $status; Item = $what; Detail = $detail }
    $colour = 'Gray'
    if ($status -eq 'OK')      { $colour = 'Green' }
    if ($status -eq 'MISSING') { $colour = 'DarkYellow' }
    if ($status -eq 'FAILED')  { $colour = 'Red' }
    if ($status -eq 'REAUTH')  { $colour = 'Cyan' }
    Write-Host ("  [{0,-7}] {1} {2}" -f $status, $what, $detail) -ForegroundColor $colour
}

function Grab-Dir($what, $src, $sub, $excludeDirs, $excludeFiles) {
    if (-not (Test-Path $src)) { Note 'MISSING' $what "($src)"; return }
    $dst = Join-Path $Destination $sub
    $a = @($src, $dst, '/E', '/R:0', '/W:0', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($excludeDirs)  { $a += '/XD'; $a += $excludeDirs }
    if ($excludeFiles) { $a += '/XF'; $a += $excludeFiles }
    $null = & robocopy @a
    if ($LASTEXITCODE -lt 8) {
        $n = @(Get-ChildItem $dst -Recurse -File -ErrorAction SilentlyContinue)
        $mb = 0; if ($n.Count) { $mb = [math]::Round(($n | Measure-Object Length -Sum).Sum / 1MB, 1) }
        Note 'OK' $what "-> $sub ($($n.Count) files, $mb MB)"
    } else { Note 'FAILED' $what "robocopy exit $LASTEXITCODE" }
}

function Grab-File($what, $src, $sub) {
    if (-not (Test-Path $src)) { Note 'MISSING' $what "($src)"; return }
    $dst = Join-Path $Destination $sub
    New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
    try { Copy-Item $src $dst -Force; Note 'OK' $what "-> $sub" }
    catch { Note 'FAILED' $what $_.Exception.Message }
}

function Grab-Text($what, $sub, $block) {
    try {
        $out = & $block 2>$null | Out-String
        $dst = Join-Path $Destination $sub
        New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
        $out | Out-File $dst -Encoding utf8
        Note 'OK' $what "-> $sub"
    } catch { Note 'FAILED' $what $_.Exception.Message }
}

# Report-only: says whether a credential store exists, never copies it.
function Note-Reauth($what, $path) {
    if (Test-Path $path) { Note 'REAUTH' $what 'exists here - sign in again on the new PC (not copied)' }
    else                 { Note 'MISSING' $what '' }
}

Write-Host ""
Write-Host "=== Claude handover collector ===" -ForegroundColor Cyan
Write-Host "  Machine     : $env:COMPUTERNAME"
Write-Host "  Destination : $Destination"
Write-Host ""

# ------------------------------------------------------- 1. CLAUDE CODE STATE
Write-Host "1. Claude Code state (the whole point of this trip)" -ForegroundColor Cyan
# The .claude tree holds: session transcripts (*.jsonl - the full record of every
# conversation), memories, global CLAUDE.md, settings, custom commands/agents/skills,
# todos and plans. Caches and the auth token are excluded.
Grab-Dir  'Claude tree (.claude)' "$env:USERPROFILE\.claude" 'claude' `
          @('shell-snapshots','statsig','cache','downloads','node_modules') `
          @('.credentials.json')
Grab-File 'Claude config (.claude.json)' "$env:USERPROFILE\.claude.json" 'claude\_claude.json'
Grab-Text 'Claude version'  'claude\_version.txt'  { claude --version }
Grab-Text 'Claude MCP list' 'claude\_mcp-list.txt' { claude mcp list }

# Explicit count of the two things that matter most, so you can see them land
$proj = "$env:USERPROFILE\.claude\projects"
if (Test-Path $proj) {
    $tx  = @(Get-ChildItem $proj -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
    $mem = @(Get-ChildItem $proj -Recurse -Path "$proj\*\memory\*" -File -ErrorAction SilentlyContinue)
    $txMB = 0; if ($tx.Count) { $txMB = [math]::Round(($tx | Measure-Object Length -Sum).Sum / 1MB, 1) }
    Note 'OK' 'Session transcripts' "$($tx.Count) files, $txMB MB"
    Note 'OK' 'Memory files'        "$($mem.Count) files"
}

# --------------------------------------------------------- 2. DEV ENVIRONMENT
Write-Host ""
Write-Host "2. Dev environment (settings, not secrets)" -ForegroundColor Cyan
Grab-File 'Git config'         "$env:USERPROFILE\.gitconfig" 'dev\.gitconfig'
Grab-File 'PowerShell history' "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadline\ConsoleHost_history.txt" 'dev\powershell-history.txt'
Grab-Dir  'VS Code user settings' "$env:APPDATA\Code\User" 'dev\vscode' @('workspaceStorage','History','globalStorage','logs') $null
Grab-Text 'VS Code extensions' 'dev\vscode-extensions.txt' { code --list-extensions }
Grab-Dir  'SSMS settings' "$env:APPDATA\Microsoft\SQL Server Management Studio" 'dev\ssms' $null $null

Write-Host "   credential stores (reported, NOT copied - re-auth on the new PC):" -ForegroundColor DarkGray
Note-Reauth 'SSH keys'       "$env:USERPROFILE\.ssh"
Note-Reauth 'Azure CLI'      "$env:USERPROFILE\.azure"
Note-Reauth 'GitHub CLI'     "$env:APPDATA\GitHub CLI\hosts.yml"

# ------------------------------------------------------------ 3. BI TOOLCHAIN
Write-Host ""
Write-Host "3. BI toolchain" -ForegroundColor Cyan
Grab-Dir 'Power BI Desktop'  "$env:APPDATA\Microsoft\Power BI Desktop" 'bi\powerbi' @('AnalysisServicesWorkspaces','TraceLogs','CEIP') $null
Grab-Dir 'PBI custom connectors' "$env:USERPROFILE\Documents\Power BI Desktop\Custom Connectors" 'bi\custom-connectors' $null $null
Grab-Dir 'Tabular Editor'    "$env:LOCALAPPDATA\TabularEditor"  'bi\tabulareditor'  @('logs') $null
Grab-Dir 'Tabular Editor 3'  "$env:LOCALAPPDATA\TabularEditor3" 'bi\tabulareditor3' @('logs') $null

# ------------------------------------------------------ 4. MACHINE / REGISTRY
Write-Host ""
Write-Host "4. Machine config" -ForegroundColor Cyan
$regDir = Join-Path $Destination 'machine'
New-Item -ItemType Directory -Path $regDir -Force | Out-Null
foreach ($r in @(
    @{ Key='HKCU\Environment';            File='env-user.reg';    What='User environment variables' },
    @{ Key='HKCU\SOFTWARE\ODBC';          File='odbc-user.reg';   What='ODBC DSNs (user)' },
    @{ Key='HKLM\SOFTWARE\ODBC\ODBC.INI'; File='odbc-system.reg'; What='ODBC DSNs (system)' }
)) {
    $out = Join-Path $regDir $r.File
    $null = & reg.exe export $r.Key $out /y 2>$null
    if (Test-Path $out) { Note 'OK' $r.What "-> machine\$($r.File)" } else { Note 'MISSING' $r.What '' }
}
Grab-Text 'Installed programs' 'machine\installed-programs.txt' {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object DisplayName | Select-Object DisplayName, DisplayVersion, Publisher |
        Sort-Object DisplayName | Format-Table -AutoSize
}
Grab-Text 'Scheduled tasks (non-Microsoft)' 'machine\scheduled-tasks.txt' {
    Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
        Select-Object TaskPath, TaskName, State | Format-Table -AutoSize
}

# ---------------------------------------------- 5. WORK LIVING OUTSIDE ONEDRIVE
Write-Host ""
Write-Host "5. Hunting for work outside OneDrive" -ForegroundColor Cyan
$strayRoots = @($env:USERPROFILE, 'C:\dev', 'C:\src', 'C:\repos', 'C:\git', 'C:\Projects', 'C:\work', 'D:\')
$found = @()
foreach ($root in $strayRoots) {
    if (-not (Test-Path $root)) { continue }
    try {
        $found += Get-ChildItem $root -Directory -Filter '.git' -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.FullName -notlike "$od*" } | Select-Object -ExpandProperty FullName
    } catch { }
}
$found = $found | Sort-Object -Unique
if ($found) {
    $found | Out-File (Join-Path $Destination 'stray-git-repos.txt') -Encoding utf8
    Note 'OK' 'Git repos outside OneDrive' "$($found.Count) found - see stray-git-repos.txt"
    Write-Host ""
    Write-Host "  !! These are NOT in OneDrive. Uncommitted work in them is not backed up:" -ForegroundColor Yellow
    $found | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
} else { Note 'OK' 'Git repos outside OneDrive' 'none found' }

$dl = Join-Path $env:USERPROFILE 'Downloads'
if (Test-Path $dl) {
    $files = @(Get-ChildItem $dl -Recurse -File -ErrorAction SilentlyContinue)
    $mb = 0; if ($files.Count) { $mb = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 1) }
    $files | Select-Object FullName, Length, LastWriteTime | Sort-Object LastWriteTime -Descending |
        Format-Table -AutoSize | Out-File (Join-Path $Destination 'downloads-inventory.txt') -Encoding utf8
    if ($mb -le $MaxDownloadsMB) { Grab-Dir "Downloads ($mb MB)" $dl 'downloads' $null $null }
    else { Note 'SKIPPED' 'Downloads' "$mb MB over the $MaxDownloadsMB MB limit - inventory written instead" }
}

# ------------------------------------------------------------- 6. MANIFEST
$total = @(Get-ChildItem $Destination -Recurse -File -ErrorAction SilentlyContinue)
$totalMB = 0; if ($total.Count) { $totalMB = [math]::Round(($total | Measure-Object Length -Sum).Sum / 1MB, 1) }

$m = @()
$m += "# Handover manifest"
$m += ""
$m += "- Machine: $env:COMPUTERNAME"
$m += "- User: $env:USERNAME"
$m += "- Collected: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$m += "- Destination: $Destination"
$m += "- Total: $($total.Count) files, $totalMB MB"
$m += ""
$m += "## Collected"
$m += ""
$m += "| Status | Item | Detail |"
$m += "|--------|------|--------|"
foreach ($l in $script:log) { $m += "| $($l.Status) | $($l.Item) | $($l.Detail) |" }
$m += ""
$m += "REAUTH = the credential store exists on the old PC but was deliberately not copied."
$m += "Sign in again on the new machine instead."
$m += ""
$m += "## NOT automated - do these by hand before wiping the machine"
$m += ""
$m += "1. **Chrome passwords, IF sync was ever off.** Anything saved while sync was off exists"
$m += "   ONLY in this machine's local profile: chrome://password-manager/settings -> Export."
$m += "   This is the one genuinely irreversible item."
$m += "2. **Authenticator app** - if your MFA authenticator lives only on this PC, move it first."
$m += "3. **Licence keys / activation** for anything installed here."
$m += "4. **Uncommitted work** in any repo listed in stray-git-repos.txt."
$m += "5. **Wait for OneDrive to say 'Your files are up to date'** before disconnecting."
$m | Out-File (Join-Path $Destination 'MANIFEST.md') -Encoding utf8

Write-Host ""
Write-Host "=== DONE: $($total.Count) files, $totalMB MB ===" -ForegroundColor Green
Write-Host "  $Destination"
Write-Host ""
Write-Host "STILL TO DO BY HAND (cannot be scripted):" -ForegroundColor Yellow
Write-Host "  1. Chrome password export IF sync was ever off (chrome://password-manager/settings)" -ForegroundColor Yellow
Write-Host "  2. Move your authenticator app if it only lives on this PC" -ForegroundColor Yellow
Write-Host "  3. WAIT for OneDrive to show 'Your files are up to date' before unplugging" -ForegroundColor Yellow
Write-Host ""
