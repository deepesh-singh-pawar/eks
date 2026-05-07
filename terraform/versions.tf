# Terraform version and provider pins so `terraform apply` behaves the same everywhere.
terraform {
  required_version = ">= 1.5.0"

  # Remote state: supply bucket/table on init.
  # terraform init -backend-config=backend.hcl
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
