# Apply-FormatStrings.ps1
# Open Dentally.pbix in Power BI Desktop first, then run this script.
# After it completes, press Ctrl+S in Power BI Desktop to save.

$pbiPath = "C:\Program Files\Microsoft Power BI Desktop\bin"

# Add PBI bin to PATH so the runtime can find native/dependent DLLs
$env:PATH = "$pbiPath;$env:PATH"

# Guard against recursive AssemblyResolve calls
$resolving = [System.Collections.Generic.HashSet[string]]::new()
$handler = [System.ResolveEventHandler]{
    param($s, $e)
    $name = [System.Reflection.AssemblyName]::new($e.Name).Name
    if (-not $resolving.Add($name)) { return $null }
    try {
        $path = Join-Path $pbiPath "$name.dll"
        if (Test-Path $path) { return [System.Reflection.Assembly]::LoadFrom($path) }
        return $null
    } finally {
        $resolving.Remove($name) | Out-Null
    }
}
[System.AppDomain]::CurrentDomain.add_AssemblyResolve($handler)

[System.Reflection.Assembly]::LoadFrom("$pbiPath\Microsoft.AnalysisServices.Server.Core.dll")    | Out-Null
[System.Reflection.Assembly]::LoadFrom("$pbiPath\Microsoft.AnalysisServices.Server.Tabular.dll") | Out-Null

# Find the msmdsrv.exe instance that has the loaded model (tables > 0)
$asProcs = Get-Process msmdsrv -ErrorAction SilentlyContinue
if (-not $asProcs) { throw "Power BI Desktop is not running. Open Dentally.pbix first." }

$server = $null
foreach ($proc in $asProcs) {
    $conns = Get-NetTCPConnection -OwningProcess $proc.Id -State Listen -ErrorAction SilentlyContinue |
             Where-Object { $_.LocalAddress -eq '127.0.0.1' }
    foreach ($conn in $conns) {
        try {
            $s = [Microsoft.AnalysisServices.Tabular.Server]::new()
            $s.Connect("localhost:$($conn.LocalPort)")
            $s.Databases[0].Refresh()
            if ($s.Databases[0].Model.Tables.Count -gt 0) {
                $server = $s
                Write-Host "Connecting to Analysis Services on port $($conn.LocalPort)..."
                break
            }
            $s.Disconnect()
        } catch {}
    }
    if ($server) { break }
}
if (-not $server) { throw "Could not find a loaded Power BI model. Is Dentally.pbix open in Power BI Desktop?" }

$model = $server.Databases[0].Model
Write-Host "Connected. Database: $($server.Databases[0].Name)  Tables: $($model.Tables.Count)"

# Format string assignments: table -> column -> format
$gbp = ([char]0x00A3) + "#,##0.00"   # £#,##0.00 via Unicode escape

$formats = [ordered]@{
    "_Invoice Items" = [ordered]@{
        "Invoice Amount"             = $gbp
        "Invoice Amount Outstanding" = $gbp
        "Invoice NHS Amount"         = $gbp
        "Item Price"                 = $gbp
        "NHS Charge"                 = $gbp
        "Quantity"                   = "#,##0.00"
        "Total Price"                = $gbp
    }
    "_Contracts" = [ordered]@{
        "UDA Target" = "#,##0.00"
        "UDA Value"  = "#,##0.00"
        "UOA Target" = "#,##0.00"
        "UOA Value"  = "#,##0.00"
    }
    "_Treatment Plan Items" = [ordered]@{
        "Price"         = $gbp
        "Duration Mins" = "#,##0"
    }
    "_Appointments" = [ordered]@{
        "Duration Mins"   = "#,##0"
        "In Surgery Mins" = "#,##0"
        "Waiting Mins"    = "#,##0"
    }
    "_Practitioner Diaries" = [ordered]@{
        "Available Clinical Mins" = "#,##0"
        "Break Count"             = "#,##0"
        "Session Duration Mins"   = "#,##0"
        "Total Break Mins"        = "#,##0"
    }
    "_Recalls" = [ordered]@{
        "Days Overdue"    = "#,##0"
        "Times Contacted" = "#,##0"
    }
    "List Accounts" = [ordered]@{
        "Current Balance"                 = $gbp
        "Opening Balance"                 = $gbp
        "Planned NHS Treatment Value"     = $gbp
        "Planned Private Treatment Value" = $gbp
    }
    "List Patients" = [ordered]@{
        "Total Invoiced"                   = $gbp
        "Total Paid"                       = $gbp
        "Age Years"                        = "#,##0"
        "Dentist Recall Interval Months"   = "#,##0"
        "Hygienist Recall Interval Months" = "#,##0"
    }
    "List Payment Plans" = [ordered]@{
        "Dentist Recall Interval Months"   = "#,##0"
        "Emergency Duration Mins"          = "#,##0"
        "Exam Duration Mins"               = "#,##0"
        "Exam Scale Polish Duration Mins"  = "#,##0"
        "Hygienist Recall Interval Months" = "#,##0"
        "Scale Polish Duration Mins"       = "#,##0"
    }
    "List Treatment Plans" = [ordered]@{
        "NHS Completed UDA Value" = "#,##0.00"
        "NHS UDA Value"           = "#,##0.00"
        "Private Treatment Value" = $gbp
    }
}

$changed  = 0
$warnings = @()

foreach ($tableEntry in $formats.GetEnumerator()) {
    $table = $model.Tables.Find($tableEntry.Key)
    if (-not $table) { $warnings += "Table not found: $($tableEntry.Key)"; continue }

    foreach ($colEntry in $tableEntry.Value.GetEnumerator()) {
        $col = $table.Columns.Find($colEntry.Key)
        if (-not $col) { $warnings += "Column not found: $($tableEntry.Key) / $($colEntry.Key)"; continue }
        $col.FormatString = $colEntry.Value
        Write-Host "  $($tableEntry.Key) / $($colEntry.Key)  ->  $($colEntry.Value)"
        $changed++
    }
}

$model.SaveChanges()
$server.Disconnect()

Write-Host "`nDone. Applied $changed format string changes."
if ($warnings) { Write-Warning "Issues:`n$($warnings -join "`n")" }
Write-Host "Press Ctrl+S in Power BI Desktop to save the file."
