# AWS provider applies default_tags to eligible resources — standard cost/ownership hygiene.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      var.common_tags,
      {
        Region = var.aws_region
      }
    )
  }
}

# TLS provider reads the OIDC issuer certificate so IAM trusts only your cluster's issuer URL.
provider "tls" {}
