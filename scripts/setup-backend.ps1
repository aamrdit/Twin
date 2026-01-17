param(
    [string]$ProjectName = "twin"
)

$ErrorActionPreference = "Stop"

Write-Host "Setting up Terraform S3 backend..." -ForegroundColor Yellow

# Navigate to terraform directory
$terraformDir = Join-Path (Split-Path $PSScriptRoot -Parent) "terraform"
Set-Location $terraformDir

# Check if backend-setup.tf exists
if (-not (Test-Path "backend-setup.tf")) {
    Write-Host "Error: backend-setup.tf not found in terraform directory" -ForegroundColor Red
    Write-Host "Please ensure backend-setup.tf exists before running this script" -ForegroundColor Yellow
    exit 1
}

# IMPORTANT: Make sure we're in the default workspace
Write-Host "Selecting default workspace..." -ForegroundColor Yellow
terraform workspace select default 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating default workspace..." -ForegroundColor Yellow
    terraform workspace new default 2>$null
}

# Initialize Terraform
Write-Host "Initializing Terraform..." -ForegroundColor Yellow
terraform init -input=false

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Terraform init failed" -ForegroundColor Red
    exit 1
}

# Apply just the backend resources
Write-Host "Applying backend resources..." -ForegroundColor Yellow
Write-Host "(This will create S3 bucket and DynamoDB table for Terraform state)" -ForegroundColor Gray
Write-Host ""

$targets = @(
    "-target=aws_s3_bucket.terraform_state",
    "-target=aws_s3_bucket_versioning.terraform_state",
    "-target=aws_s3_bucket_server_side_encryption_configuration.terraform_state",
    "-target=aws_s3_bucket_public_access_block.terraform_state",
    "-target=aws_dynamodb_table.terraform_locks"
)

& terraform apply $targets -auto-approve

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Terraform apply failed" -ForegroundColor Red
    exit 1
}

# Verify the resources were created
Write-Host ""
Write-Host "Verifying resources..." -ForegroundColor Yellow
Write-Host ""

$stateBucket = terraform output -raw state_bucket_name 2>$null
$dynamodbTable = terraform output -raw dynamodb_table_name 2>$null

if ($stateBucket -and $dynamodbTable) {
    Write-Host "✅ Backend setup complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "State Bucket   : $stateBucket" -ForegroundColor Cyan
    Write-Host "DynamoDB Table : $dynamodbTable" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Remove backend-setup.tf: Remove-Item terraform\backend-setup.tf" -ForegroundColor White
    Write-Host "2. Create terraform/backend.tf (see documentation)" -ForegroundColor White
    Write-Host "3. Update deployment scripts to use S3 backend" -ForegroundColor White
} else {
    Write-Host "Warning: Could not retrieve outputs. Resources may still be creating..." -ForegroundColor Yellow
    Write-Host "Run 'terraform output' to check manually" -ForegroundColor Gray
}

