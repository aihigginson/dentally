<#
.SYNOPSIS
    Copy data from Audit and Bronze schemas on-prem into the Fabric Warehouse.
.DESCRIPTION
    Reads each table from on-prem (Windows Auth) using SqlDataAdapter, generates
    batched INSERT statements, and executes them against Fabric via sqlcmd.
    Fabric does not support BCP INSERT BULK, so this avoids that entirely.
    Prompts once for your Fabric password. Truncates target tables before inserting
    so reruns are safe.
.PARAMETER OnPremServer
    On-premises SQL Server instance, e.g. HST\HS2
.PARAMETER OnPremDatabase
    On-premises database name, e.g. Dentally
.PARAMETER FabricServer
    Fabric Warehouse SQL endpoint.
.PARAMETER FabricDatabase
    Fabric Warehouse database name.
.PARAMETER FabricUser
    Azure AD email address for Fabric.
.PARAMETER Schemas
    Schemas to migrate. Defaults to Audit and Bronze.
.EXAMPLE
    .\Migrate_Data_To_Fabric.ps1 `
        -OnPremServer   "HST\HS2" `
        -OnPremDatabase "Dentally" `
        -FabricServer   "rfgx72m2ckiuzetkplc54cbksu-rhorptch4uoenghfp4noadcjn4.datawarehouse.fabric.microsoft.com" `
        -FabricDatabase "WH_Dentally" `
        -FabricUser     "aihigginson@2rrjxy.onmicrosoft.com"
#>
param(
    [Parameter(Mandatory)] [string]   $OnPremServer,
    [Parameter(Mandatory)] [string]   $OnPremDatabase,
    [Parameter(Mandatory)] [string]   $FabricServer,
    [Parameter(Mandatory)] [string]   $FabricDatabase,
    [Parameter(Mandatory)] [string]   $FabricUser,
    [string[]] $Schemas = @('Audit', 'Bronze')
)

if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { Write-Error "sqlcmd.exe not found."; exit 1 }

# Prompt once - password reused for every sqlcmd call
$securePwd = Read-Host "Fabric password for $FabricUser" -AsSecureString
$bstr      = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePwd)
$pwd       = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

# Quick connection test
Write-Host "Testing Fabric connection..." -NoNewline
$testOut = & sqlcmd -S $FabricServer -d $FabricDatabase -G -U $FabricUser -P $pwd -Q "SELECT 1" -b 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host " FAILED" -ForegroundColor Red
    $testOut | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkRed }
    exit 1
}
Write-Host " OK" -ForegroundColor Green

# Discover tables on-prem
$schemaList = ($Schemas | ForEach-Object { "'$_'" }) -join ', '
$tables = Invoke-Sqlcmd `
    -ServerInstance $OnPremServer `
    -Database       $OnPremDatabase `
    -TrustServerCertificate `
    -Query "
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM   INFORMATION_SCHEMA.TABLES
        WHERE  TABLE_SCHEMA IN ($schemaList)
          AND  TABLE_TYPE = 'BASE TABLE'
        ORDER  BY TABLE_SCHEMA, TABLE_NAME"

Write-Host "`nMigrating $($tables.Count) tables: $OnPremDatabase -> $FabricDatabase`n"

# Format a single column value as a SQL literal
function Format-SqlValue {
    param($v)
    if ($v -is [System.DBNull] -or $null -eq $v) { return 'NULL' }
    if ($v -is [string])        { return "'" + $v.Replace("'", "''") + "'" }
    if ($v -is [System.DateTime]) { return "'" + $v.ToString('yyyy-MM-dd HH:mm:ss.ffffff') + "'" }
    if ($v -is [System.Guid])   { return "'" + $v.ToString() + "'" }
    if ($v -is [bool])          { return if ($v) { '1' } else { '0' } }
    return $v.ToString()
}

$onPremConnStr = "Server=$OnPremServer;Database=$OnPremDatabase;Integrated Security=True;TrustServerCertificate=True;"
$batchSize     = 500
$failed        = @()
$tmpSql        = Join-Path $env:TEMP "fabric_migrate.sql"

foreach ($row in $tables) {
    $schema = $row.TABLE_SCHEMA
    $table  = $row.TABLE_NAME
    $label  = "$schema.$table"

    Write-Host "  $label" -NoNewline

    # Read all rows from on-prem into a DataTable
    $conn    = New-Object System.Data.SqlClient.SqlConnection $onPremConnStr
    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter("SELECT * FROM [$schema].[$table]", $conn)
    $dt      = New-Object System.Data.DataTable
    try {
        $adapter.Fill($dt) | Out-Null
    } catch {
        Write-Host "  READ FAILED" -ForegroundColor Red
        Write-Host "    $_" -ForegroundColor DarkRed
        $failed += "$label (read)"
        $conn.Dispose()
        continue
    } finally {
        $conn.Dispose()
    }

    Write-Host "  $($dt.Rows.Count) rows..." -NoNewline

    # Build column list
    $colList = ($dt.Columns | ForEach-Object { "[$($_.ColumnName)]" }) -join ', '

    # Generate SQL script: DELETE first, then batched INSERTs
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("DELETE FROM [$schema].[$table];")
    $lines.Add("GO")

    $i = 0
    foreach ($dataRow in $dt.Rows) {
        $vals = $dt.Columns | ForEach-Object { Format-SqlValue $dataRow[$_.ColumnName] }
        $lines.Add("INSERT INTO [$schema].[$table] ($colList) VALUES (" + ($vals -join ', ') + ");")
        $i++
        if ($i % $batchSize -eq 0) { $lines.Add("GO") }
    }
    $lines.Add("GO")

    [System.IO.File]::WriteAllLines($tmpSql, $lines, [System.Text.Encoding]::UTF8)

    # Execute against Fabric
    $out = & sqlcmd -S $FabricServer -d $FabricDatabase -G -U $FabricUser -P $pwd -i $tmpSql -b 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  IMPORT FAILED" -ForegroundColor Red
        # Show first error line only to keep output readable
        $out | Where-Object { $_ -match 'Error|error|Msg' } | Select-Object -First 3 |
            ForEach-Object { Write-Host "    $_" -ForegroundColor DarkRed }
        $failed += $label
    } else {
        Write-Host "  done." -ForegroundColor Green
    }
}

Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue

# Update Environment_Config in Fabric
Write-Host "`nUpdating Audit.Environment_Config..."
$configSql = @"
DELETE FROM Audit.Environment_Config WHERE Env_Config_Key IN ('workspace_name','lakehouse_name','warehouse_name');
INSERT INTO Audit.Environment_Config (Env_Config_Key, Env_Config_Value) VALUES ('workspace_name', 'DEV - DM Dentally');
INSERT INTO Audit.Environment_Config (Env_Config_Key, Env_Config_Value) VALUES ('lakehouse_name', 'LH_Dentally');
INSERT INTO Audit.Environment_Config (Env_Config_Key, Env_Config_Value) VALUES ('warehouse_name', 'WH_Dentally');
GO
"@
[System.IO.File]::WriteAllText($tmpSql, $configSql, [System.Text.Encoding]::UTF8)
& sqlcmd -S $FabricServer -d $FabricDatabase -G -U $FabricUser -P $pwd -i $tmpSql -b
if ($LASTEXITCODE -eq 0) {
    Write-Host "  Environment_Config updated." -ForegroundColor Green
} else {
    Write-Warning "  Environment_Config update failed - run manually if needed."
}
Remove-Item $tmpSql -Force -ErrorAction SilentlyContinue

$pwd = $null

# Summary
Write-Host "`n$('-' * 60)"
if ($failed.Count -eq 0) {
    Write-Host "All $($tables.Count) tables migrated successfully." -ForegroundColor Green
} else {
    Write-Host "$($failed.Count) failure(s):" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
