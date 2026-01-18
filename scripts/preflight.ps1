param (
    [string]$envName = "dev"
)

# Resolve Terraform directory
$terraformDir = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath "..\terraform") | Select-Object -ExpandProperty Path

if (-Not (Test-Path $terraformDir)) {
    Write-Error "Terraform directory not found at $terraformDir. Please check the path."
    exit 1
}

# Set AWS region
$Env:AWS_REGION = "eu-central-1"
$Env:AWS_DEFAULT_REGION = "eu-central-1"

Write-Host "🌍 AWS Region set to $Env:AWS_REGION"
Write-Host "📂 Terraform directory: $terraformDir"
Write-Host "⚙️ Environment: $envName"

# Initialize Terraform backend
Write-Host "`n🚀 Initializing Terraform backend..."
terraform -chdir="$terraformDir" init `
  -backend-config="bucket=twin-terraform-state-246728976544" `
  -backend-config="key=terraform.tfstate" `
  -backend-config="region=eu-central-1" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -reconfigure

# Select or create workspace
Write-Host "`n🗂 Selecting or creating workspace '$envName'..."
terraform -chdir="$terraformDir" workspace select $envName -or-create

# Run Terraform plan
Write-Host "`n📝 Running Terraform plan..."
terraform -chdir="$terraformDir" plan

Write-Host "`n✅ Preflight completed! Workspace '$envName' is ready."
