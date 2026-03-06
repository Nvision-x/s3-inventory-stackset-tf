terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

module "s3_inventory_per_account" {
  source = "./modules/per-account"

  collector_bucket_prefix  = var.collector_bucket_prefix
  collector_account_id     = var.collector_account_id
  inventory_name           = var.inventory_name
  output_format            = var.output_format
  schedule_frequency       = var.schedule_frequency
  included_object_versions = var.included_object_versions
  schedule_expression      = var.schedule_expression
  test_mode                = var.test_mode
  test_bucket_name         = var.test_bucket_name
  exclude_bucket_prefixes  = var.exclude_bucket_prefixes
  exclude_bucket_tag       = var.exclude_bucket_tag
  lambda_timeout           = var.lambda_timeout
  log_retention_days       = var.log_retention_days
  tags                     = var.tags
}
