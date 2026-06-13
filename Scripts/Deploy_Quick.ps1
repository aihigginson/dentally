<#
.SYNOPSIS
    Deploy one or more Fabric SQL files without running the full pipeline.
.DESCRIPTION
    Pass a list of filenames (no path — just the file name from the Fabric/ folder)
    and they are concatenated and executed against the Fabric Warehouse in order.
    Connection details default to the dev warehouse; override via parameters.
.PARAMETER Files
    One or more SQL file names from the Fabric/ folder, e.g.:
      Gold.usp_Load_Fact_KPI_Snapshot.StoredProcedure.sql
      Gold.Fact_KPI_Snapshot.Table.sql
.PARAMETER Server
    Fabric SQL endpoint (defaults to dev workspace).
.PARAMETER Database
    Fabric Warehouse name (defaults to WH_Dentally).
.PARAMETER Username
    Azure AD email (defaults to admin@Analytically.info).
.EXAMPLE
    .\Deploy_Quick.ps1 Gold.usp_Load_Fact_KPI_Snapshot.StoredProcedure.sql
.EXAMPLE
    .\Deploy_Quick.ps1 Gold.Fact_KPI_Snapshot.Table.sql, Gold.usp_Load_Fact_KPI_Snapshot.StoredProcedure.sql
#>
param(
    [Parameter(Mandatory, Position = 0)]
    [string[]] $Files,

    [string] $Server   = "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com",
    [string] $Database = "WH_Dentally",
    [string] $Username = "admin@Analytically.info"
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    Write-Error "sqlcmd.exe not found."
    exit 1
}

$FabricDir = Join-Path $PSScriptRoot '..\Fabric'

$securePwd = Read-Host "Fabric password for $Username" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

$combined = [System.Text.StringBuilder]::new()

foreach ($file in $Files) {
    $path = Join-Path $FabricDir $file
    if (-not (Test-Path $path)) {
        Write-Error "File not found: $path"
        exit 1
    }
    $null = $combined.AppendLine("PRINT '  FILE: $file';")
    $null = $combined.AppendLine("GO")
    $null = $combined.AppendLine([System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8))
    $null = $combined.AppendLine()
}

$tmpFile = Join-Path $env:TEMP "Deploy_Quick_$(Get-Date -Format 'yyyyMMdd_HHmmss').sql"
[System.IO.File]::WriteAllText($tmpFile, $combined.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "Deploying $($Files.Count) file(s) to $Database @ $Server" -ForegroundColor Cyan
$Files | ForEach-Object { Write-Host "  $_" }

& sqlcmd -S $Server -d $Database -G -U $Username -P $pwd -i "$tmpFile" -b
$rc = $LASTEXITCODE

Remove-Item $tmpFile -Force

Write-Host "`n$('─' * 60)"
if ($rc -eq 0) {
    Write-Host "Complete." -ForegroundColor Green
} else {
    Write-Host "Deployment finished with errors (see above). Exit code: $rc" -ForegroundColor Red
}
