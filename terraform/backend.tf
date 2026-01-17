terraform {
  backend "s3" {
    bucket         = "twin-terraform-state-246728976544"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "twin-terraform-locks"
  }
}
