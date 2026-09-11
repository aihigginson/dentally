<#
.SYNOPSIS
    Copies Claude Code's session transcripts out of %USERPROFILE%\.claude into OneDrive
    so they survive the machine. Safe to run repeatedly - unchanged files are skipped.

.DESCRIPTION
    Claude keeps each session verbatim in:
        %USERPROFILE%\.claude\projects\<project-slug>\<session-uuid>.jsonl
    plus a sibling <session-uuid>\tool-results\ folder holding oversized tool output.

    That tree is OUTSIDE OneDrive, so it is not synced, not backed up, and dies with the
    machine - the same trap that lost the memories in the Sep 2026 PC move. Memories were
    fixed with a directory junction (SETUP.md section 8); transcripts cannot use the same
    trick because Claude appends to the live .jsonl continuously and OneDrive would churn
    on every write. So this copies on demand instead.

    Default destination:
        <OneDrive>\ClaudeTranscripts\<COMPUTERNAME>\<project-slug>\

    That sits OUTSIDE the repo on purpose. A transcript is a verbatim record of the
    session - warehouse connection strings, real patient and practitioner names, whatever
    was pasted in - so it must never be committed. The script refuses to write anywhere
    inside a git working tree.

    The live session's .jsonl is open for append while Claude is running, so the copy is a
    point-in-time snapshot taken with a shared read handle. Re-run it at the end of a
    session to capture the tail.

.PARAMETER Destination
    Override the destination root. Rejected if it resolves inside a git repository.

.PARAMETER Project
    Only back up project slugs matching this wildcard, e.g. '*dentally*'.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File Scripts\Backup-ClaudeTranscripts.ps1

.EXAMPLE
    .\Scripts\Backup-ClaudeTranscripts.ps1 -Project '*dentally*'
#>
[CmdletBinding()]
param(
    [string] $Destination,
    [string] $Project = '*'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- source
$src = Join-Path $env:USERPROFILE '.claude\projects'
if (-not (Test-Path $src)) {
    Write-Host "FATAL: no Claude project folder at $src" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------- destination
if (-not $Destination) {
    $od = $env:OneDrive
    if (-not $od) { $od = $env:OneDriveConsumer }
    if (-not $od) { $od = Join-Path $env:USERPROFILE 'OneDrive' }
    if (-not (Test-Path $od)) {
        Write-Host "FATAL: no OneDrive folder found. Re-run with -Destination <path>." -ForegroundColor Red
        exit 1
    }
    $Destination = Join-Path $od "ClaudeTranscripts\$env:COMPUTERNAME"
}

# Never let a verbatim transcript land somewhere git could pick it up.
$probe = $Destination
while ($probe -and (Split-Path $probe -Parent)) {
    if (Test-Path (Join-Path $probe '.git')) {
        Write-Host "FATAL: $Destination is inside the git repo at $probe." -ForegroundColor Red
        Write-Host "       Transcripts are unredacted and must not be committed." -ForegroundColor Red
        exit 1
    }
    $probe = Split-Path $probe -Parent
}
New-Item -ItemType Directory -Path $Destination -Force | Out-Null

# ---------------------------------------------------------------- helpers
# Copy-Item fails on the live .jsonl (Claude holds it open for append), so open the
# source with FileShare.ReadWrite and stream it out ourselves.
function Copy-Shared {
    param([string] $From, [string] $To)
    $in = $null; $out = $null
    try {
        $in  = [System.IO.File]::Open($From, [System.IO.FileMode]::Open,
                                      [System.IO.FileAccess]::Read,
                                      [System.IO.FileShare]::ReadWrite)
        $out = [System.IO.File]::Create($To)
        $in.CopyTo($out)
        return $true
    } catch {
        Write-Host "    FAILED $([System.IO.Path]::GetFileName($From)): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if ($out) { $out.Dispose() }
        if ($in)  { $in.Dispose() }
    }
}

function Should-Copy {
    param([System.IO.FileInfo] $Source, [string] $Target)
    if (-not (Test-Path $Target)) { return $true }
    $t = Get-Item $Target
    # A live transcript only ever grows, so length is the reliable signal.
    return ($t.Length -ne $Source.Length -or $t.LastWriteTimeUtc -lt $Source.LastWriteTimeUtc)
}

# ---------------------------------------------------------------- run
Write-Host "=== Claude transcript backup ===" -ForegroundColor Cyan
Write-Host "  Source      : $src"
Write-Host "  Destination : $Destination"
Write-Host ""

$copied = 0; $skipped = 0; $failed = 0; $bytes = 0L

foreach ($proj in Get-ChildItem $src -Directory | Where-Object Name -Like $Project) {
    $files = @(Get-ChildItem $proj.FullName -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)
    # Skip reparse points. The 'memory' junction points back into the repo, so following it
    # would duplicate version-controlled files into the backup for no reason.
    $extra = @(Get-ChildItem $proj.FullName -Directory -ErrorAction SilentlyContinue |
               Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
               ForEach-Object { Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue })
    if (-not $files -and -not $extra) { continue }

    Write-Host $proj.Name -ForegroundColor Yellow
    $projDst = Join-Path $Destination $proj.Name
    New-Item -ItemType Directory -Path $projDst -Force | Out-Null

    foreach ($f in ($files + $extra)) {
        # keep the tool-results/ shape under the session folder
        $rel = $f.FullName.Substring($proj.FullName.Length).TrimStart('\')
        $to  = Join-Path $projDst $rel
        New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force | Out-Null

        if (-not (Should-Copy $f $to)) {
            $skipped++
            continue
        }
        if (Copy-Shared $f.FullName $to) {
            $copied++; $bytes += $f.Length
            Write-Host ("    {0,-46} {1,8:N0} KB" -f $rel, ($f.Length / 1KB)) -ForegroundColor Green
        } else {
            $failed++
        }
    }
}

Write-Host ""
Write-Host ("copied {0} file(s), {1:N1} MB   skipped {2} unchanged   failed {3}" -f `
            $copied, ($bytes / 1MB), $skipped, $failed) -ForegroundColor Cyan
Write-Host "OneDrive will sync these; give it a minute before wiping anything."

if ($failed) { exit 1 }
