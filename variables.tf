variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "collector_bucket_prefix" {
  description = "Prefix for regional collector buckets"
  type        = string
  default     = "nvisionx-s3-inventory"
}

variable "collector_account_id" {
  description = "AWS Account ID where the collector buckets reside"
  type        = string
}

variable "inventory_name" {
  description = "Name/ID of the inventory configuration applied to each bucket"
  type        = string
  default     = "terra-s3-inv"
}

variable "output_format" {
  description = "Output format for inventory files"
  type        = string
  default     = "Parquet"
}

variable "schedule_frequency" {
  description = "How often inventory reports are generated"
  type        = string
  default     = "Daily"
}

variable "included_object_versions" {
  description = "Which object versions to include in inventory"
  type        = string
  default     = "All"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression for daily Lambda trigger"
  type        = string
  default     = "rate(1 day)"
}

variable "test_mode" {
  description = "When true, Lambda only processes the single bucket specified in test_bucket_name"
  type        = string
  default     = "false"
}

variable "test_bucket_name" {
  description = "S3 bucket name to use for testing"
  type        = string
  default     = ""
}

variable "exclude_bucket_prefixes" {
  description = "Comma-separated list of bucket name prefixes to exclude"
  type        = string
  default     = ""
}

variable "exclude_bucket_tag" {
  description = "Tag key to check on buckets for exclusion"
  type        = string
  default     = "SkipInventory"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
