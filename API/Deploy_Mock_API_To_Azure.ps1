<#
.SYNOPSIS
    Deploy the Dentally mock API to Azure App Service (no Docker required).
.DESCRIPTION
    Creates an Azure App Service (Python 3.11, B1 tier) and deploys the Flask
    app directly from source. Gives a stable public HTTPS endpoint.
    Re-run after code changes to redeploy.
.PARAMETER ResourceGroup
    Azure resource group name. Created if it does not exist.
.PARAMETER Location
    Azure region. Defaults to uksouth.
.PARAMETER AppName
    App Service name. Must be globally unique — becomes <AppName>.azurewebsites.net.
.PARAMETER ApiKey
    API key the Flask app will require in the Authorization header.
    Store this somewhere safe — you will need it in the Fabric notebook.
.EXAMPLE
    .\Deploy_Mock_API_To_Azure.ps1
.EXAMPLE
    .\Deploy_Mock_API_To_Azure.ps1 -AppName "dentally-mock-yourname" -ApiKey "my-secret-key"
#>
param(
    [string] $ResourceGroup = "rg-dentally-dev",
    [string] $Location      = "uksouth",
    [string] $AppName       = "dentally-mock-api",
    [string] $ApiKey        = "dev-mock-key-abc123"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# -- Prerequisites check -------------------------------------------------------

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Error "Azure CLI (az) not found. Install from https://aka.ms/installazurecliwindows"
    exit 1
}

Write-Host "Deploying Dentally Mock API to Azure App Service" -ForegroundColor Cyan
Write-Host "Resource group : $ResourceGroup"
Write-Host "Location       : $Location"
Write-Host "App name       : $AppName"
Write-Host "URL            : https://$AppName.azurewebsites.net"
Write-Host ""

# -- Login check ---------------------------------------------------------------

$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in to Azure. Running az login..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "Logged in as  : $($account.user.name)" -ForegroundColor Green
Write-Host "Subscription  : $($account.name)"
Write-Host ""

# -- Resource group ------------------------------------------------------------

$rgExists = az group exists --name $ResourceGroup
if ($rgExists -eq "false") {
    Write-Host "Creating resource group $ResourceGroup..."
    az group create --name $ResourceGroup --location $Location | Out-Null
    Write-Host "Resource group created." -ForegroundColor Green
} else {
    Write-Host "Resource group $ResourceGroup already exists."
}

# -- Deploy to App Service -----------------------------------------------------
# az webapp up creates the App Service plan and web app if they don't exist,
# then zips and deploys the source code. Re-running it redeploys the code.

Write-Host "Deploying app (this takes ~2 minutes on first run)..."
Push-Location $ScriptDir

az webapp up `
    --name         $AppName `
    --resource-group $ResourceGroup `
    --location     $Location `
    --runtime      "PYTHON:3.11" `
    --sku          B1

if ($LASTEXITCODE -ne 0) {
    Pop-Location
    Write-Error "Deployment failed."
    exit 1
}

Pop-Location

# -- Configure API key and startup command ------------------------------------

Write-Host "Configuring environment variables..."
az webapp config appsettings set `
    --name           $AppName `
    --resource-group $ResourceGroup `
    --settings       DENTALLY_API_KEY=$ApiKey | Out-Null

Write-Host "Configuring startup command..."
az webapp config set `
    --name           $AppName `
    --resource-group $ResourceGroup `
    --startup-file   "gunicorn --bind=0.0.0.0 --timeout 600 mock_api:app" | Out-Null

Write-Host "Restarting app to pick up config changes..."
az webapp restart --name $AppName --resource-group $ResourceGroup | Out-Null

# -- Result --------------------------------------------------------------------

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "Deployment complete." -ForegroundColor Green
Write-Host ""
Write-Host "API base URL : https://$AppName.azurewebsites.net"
Write-Host "API key      : $ApiKey"
Write-Host ""
Write-Host "Test it (run in a new terminal):"
Write-Host "  Invoke-RestMethod -Uri 'https://$AppName.azurewebsites.net/'"
Write-Host "  Invoke-RestMethod -Uri 'https://$AppName.azurewebsites.net/v1/patients?per_page=2' -Headers @{ Authorization = 'Bearer $ApiKey' }"
Write-Host ("=" * 60) -ForegroundColor Green
