# ---------------------------------------------------------------------------
# Deploy_Template_Gold.ps1  --  COPY AND RENAME BEFORE USE
# ---------------------------------------------------------------------------
# New name  : Deploy_vNNN_Description.ps1  (NNN = next sequential number)
# Version   : NNN
# Date      : YYYY-MM-DD
# Author    : AIH
# Layer     : Gold
# Changes   : <what changed and why>
# After     : Refresh PBI dataset.
#
# Use this template when:
#   - Updating Gold usp_Create_* or usp_Load_* stored procedures
#   - Optionally running the SPs immediately after deploy to refresh Gold data
#
# Notes:
#   - Gold tables are full-rebuild (DROP/CREATE). No schema migration needed.
#     If the table structure changed, include usp_Create_* and set $RunCreate.
#   - If this is a logic-only SP fix, skip usp_Create_* and set $RunCreate = $false.
#   - $RunLoad = $true runs the Load SP inline and prints I/U/D counts.
#   - If ONLY updating a single SP (no inline run needed), Deploy_Quick.ps1 is simpler.
# ---------------------------------------------------------------------------

param(
    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "admin@Analytically.info"
)

# ---------------------------------------------------------------------------
# Configuration -- edit these for each new deploy
# ---------------------------------------------------------------------------

# SP names (schema.name format, no brackets)
$CreateProc = ''              # e.g. 'Gold.usp_Create_Dim_YourEntity'  -- leave blank to skip
$LoadProc   = ''              # e.g. 'Gold.usp_Load_Dim_YourEntity'

# Set to $true to run the SP inline after deploying it
$RunCreate  = $false
$RunLoad    = $true

# SQL files to deploy (filenames only -- looked up from ..\Fabric\)
$DeployFiles = @(
    # 'Gold.YourEntity.Table.sql'                          # include if table structure changed
    # 'Gold.usp_Create_YourEntity.StoredProcedure.sql'    # include if create proc changed
    # 'Gold.usp_Load_YourEntity.StoredProcedure.sql'      # include if load proc changed
)

# ---------------------------------------------------------------------------

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$Errors = 0

function Invoke-SQL($sql, $label) {
    $tmp = [System.IO.Path]::GetTempFileName() + ".sql"
    [System.IO.File]::WriteAllText($tmp, $sql, [System.Text.Encoding]::UTF8)
    Write-Host "  $label" -NoNewline
    & sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i $tmp -b | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAILED" -ForegroundColor Red
        $script:Errors++
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
    Remove-Item $tmp -Force
}

function Deploy-File($file, $label) {
    $path = Join-Path $FabricDir $file
    if (-not (Test-Path $path)) { Write-Error "File not found: $path"; $script:Errors++; return }
    Invoke-SQL ([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)) $label
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== 1. Deploy SQL files ===" -ForegroundColor Cyan
# ---------------------------------------------------------------------------

if ($DeployFiles.Count -eq 0) {
    Write-Error "No files listed in `$DeployFiles. Fill in the configuration block."
    exit 1
}

foreach ($file in $DeployFiles) {
    Deploy-File $file $file
}

if ($Errors -gt 0) { Write-Host "Aborting -- deploy failed." -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
if ($RunCreate -and $CreateProc) {
    Write-Host ""
    Write-Host "=== 2. Run $CreateProc ===" -ForegroundColor Cyan
    Invoke-SQL "EXEC $CreateProc;" "Run $CreateProc"
    if ($Errors -gt 0) { Write-Host "Aborting -- Create proc failed." -ForegroundColor Red; exit 1 }
}

# ---------------------------------------------------------------------------
if ($RunLoad -and $LoadProc) {
    Write-Host ""
    Write-Host "=== 3. Run $LoadProc ===" -ForegroundColor Cyan
    $sql = @"
DECLARE @i BIGINT, @u BIGINT, @d BIGINT;
EXEC $LoadProc
     @Mode        = 'PROD',
     @Run_Inserts = @i OUT,
     @Run_Updates = @u OUT,
     @Run_Deletes = @d OUT;
PRINT CONCAT('$LoadProc  I=', @i, '  U=', @u, '  D=', @d);
"@
    Invoke-SQL $sql "Run $LoadProc"
}

# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "$('─' * 60)"
if ($Errors -eq 0) {
    Write-Host "Complete." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Refresh the PBI dataset to pick up Gold changes."
    Write-Host "  2. Verify KPI values on affected PBI pages."
} else {
    Write-Host "Finished with $Errors error(s) -- review output above." -ForegroundColor Red
    exit 1
}
