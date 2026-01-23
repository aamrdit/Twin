# This file creates the S3 bucket and DynamoDB table for Terraform state.
# Run this once per AWS account (bootstrap), then keep it in the terraform-bootstrap stack.
# IMPORTANT: We add prevent_destroy to protect the backend from accidental teardown.

resource "aws_s3_bucket" "terraform_state" {
  bucket = "twin-terraform-state-${data.aws_caller_identity.current.account_id}"

  # Protect the state bucket from being destroyed by mistake.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Terraform State Store"
    Environment = "global"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "twin-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  # Protect the lock table from being destroyed by mistake.
  lifecycle {
    prevent_destroy = true
  }

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Terraform State Locks"
    Environment = "global"
    ManagedBy   = "terraform"
  }
}

# Note: aws_caller_identity.current is already defined in main.tf

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}
