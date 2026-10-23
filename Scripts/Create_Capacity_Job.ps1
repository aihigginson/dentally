# =====================================================================
# Create_Capacity_Job.ps1 -- one-off: stand up caj-capacity-schedule-prod.
#
# Run once. It is here so the job's shape is in git rather than only in the portal,
# and so it can be recreated without archaeology. Safe to re-run: it reports what
# already exists instead of duplicating it.
#
#   az login            <- MUST be an MFA session; Azure refuses resource creation
#                          from a non-MFA token with RequestDisallowedByAzure
#   .\Scripts\Create_Capacity_Job.ps1
#
# ==> THE JOB AUTHENTICATES AS ITSELF. <== It gets a system-assigned managed identity
# and exactly one role assignment, Contributor scoped to the CAPACITY RESOURCE -- not
# the resource group. The app's service principal is not reused: it holds no rights
# over Azure resources at all, and the point of this job is not to change that.
#
# ==> ErrorActionPreference STAYS 'Continue'. <== The containerapp extension prints
# "WARNING: The behavior of this command has been altered by the following extension"
# to STDERR on every single call. Under 'Stop', PowerShell promotes native stderr to a
# terminating NativeCommandError, so the script dies on line one with a stack trace
# about a notice that means nothing. Exit codes are checked explicitly instead.
# =====================================================================
$ErrorActionPreference = 'Continue'

$rg       = 'rg-analytically'
$job      = 'caj-capacity-schedule-prod'
$envName  = 'cae-analytically'
$image    = 'analyticallyacr.azurecr.io/analytically:latest'
$registry = 'analyticallyacr.azurecr.io'
$sub      = 'b24ec454-d0b6-4a06-8063-ee59335558b8'
$scope    = "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Fabric/capacities/analytically"

# Hourly at :45, with the script's own 15-minute lead: every firing asks "what should be
# true at the top of the next hour?". Hourly rather than only at the four boundaries so a
# failed or missed run is corrected within the hour instead of leaving the capacity on the
# wrong SKU overnight. A run that has nothing to do exits in a couple of seconds.
$cron = '45 * * * *'

# ==> NEVER NAME A HELPER AFTER THE CLI IT WRAPS. <== A function called `Az` shadows the
# `az` command inside its own body -- PowerShell resolves FUNCTIONS before external
# commands, case-insensitively -- so `& az @args` re-entered the helper instead of running
# the CLI. $LASTEXITCODE was never set, and the failure surfaced as "failed ()" with an
# empty exit code on a command that is perfectly valid.
function Invoke-AzCli {
    param([string[]] $Arguments, [switch] $AllowFail)
    $out  = & az @Arguments 2>&1
    $code = $LASTEXITCODE
    # The containerapp extension prints a WARNING to stderr on every call; it is noise.
    $text = (($out | Where-Object { "$_" -notmatch '^WARNING:' }) -join [Environment]::NewLine).Trim()
    if ($code -ne 0) {
        if ($AllowFail) { return '' }
        throw "az $($Arguments -join ' ') exited $code$([Environment]::NewLine)$text"
    }
    $text
}

# ---- 1. the job ---------------------------------------------------------------------
if (Invoke-AzCli @('containerapp','job','show','-n',$job,'-g',$rg,'--query','name','-o','tsv') -AllowFail) {
    Write-Host "$job already exists -- skipping create." -ForegroundColor Yellow
} else {
    Write-Host "Creating $job ..." -ForegroundColor Cyan
    Invoke-AzCli @(
        'containerapp','job','create',
        '-n',$job,'-g',$rg,
        '--environment',$envName,
        '--trigger-type','Schedule','--cron-expression',$cron,
        '--replica-timeout','600','--replica-retry-limit','1',
        '--parallelism','1','--replica-completion-count','1',
        '--image',$image,
        '--cpu','0.5','--memory','1Gi',
        '--mi-system-assigned',
        '--registry-server',$registry,
        '--command','python','--args','capacity_schedule.py',
        '-o','none') | Out-Null
    Write-Host 'created.' -ForegroundColor Green
}

# ---- 2. the one role assignment it needs --------------------------------------------
$principal = Invoke-AzCli @('containerapp','job','show','-n',$job,'-g',$rg,'--query','identity.principalId','-o','tsv')
if (-not $principal) { throw 'The job has no system-assigned identity.' }
Write-Host "managed identity: $principal"

$existing = Invoke-AzCli @('role','assignment','list','--assignee',$principal,'--scope',$scope,
    '--query',"[?roleDefinitionName=='Contributor'] | [0].id",'-o','tsv') -AllowFail
if ($existing) {
    Write-Host 'Contributor on the capacity already granted.' -ForegroundColor Yellow
} else {
    Write-Host 'Granting Contributor on the capacity resource ...' -ForegroundColor Cyan
    Invoke-AzCli @('role','assignment','create','--assignee-object-id',$principal,
        '--assignee-principal-type','ServicePrincipal',
        '--role','Contributor','--scope',$scope,'-o','none') | Out-Null
    Write-Host 'waiting 30s for the assignment to propagate ...'
    Start-Sleep 30
}

# ---- 3. prove it, without changing anything -----------------------------------------
# A job execution is the only honest test: it exercises the image, the identity and the
# role assignment together. --dry-run reads the capacity and reports, nothing more.
Write-Host "`nStarting a dry-run execution ..." -ForegroundColor Cyan
$exec = Invoke-AzCli @('containerapp','job','start','-n',$job,'-g',$rg,
    '--command','python','--args','capacity_schedule.py','--args','--dry-run',
    '--query','name','-o','tsv')
Write-Host "execution: $exec"

$status = ''
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep 10
    $status = Invoke-AzCli @('containerapp','job','execution','show','-n',$job,'-g',$rg,
        '--job-execution-name',$exec,'--query','properties.status','-o','tsv') -AllowFail
    if ($status -and $status -notin @('Running', 'Processing')) { break }
}
Write-Host "status: $status" -ForegroundColor $(if ($status -eq 'Succeeded') { 'Green' } else { 'Red' })

Write-Host "`nlogs:"
& az containerapp job logs show -n $job -g $rg --execution $exec --container $job --tail 30 2>&1 |
    Where-Object { "$_" -notmatch '^WARNING:' }

Write-Host "`nIf that said 'target <SKU>; capacity is <SKU>, Active' the job is live." -ForegroundColor Green
Write-Host "Next firing is the next :45. Watch it with:"
Write-Host "  az containerapp job execution list -n $job -g $rg -o table"
