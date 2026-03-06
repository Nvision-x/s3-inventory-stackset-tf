variable "collector_bucket_prefix" {
  description = "Prefix for regional collector buckets. Destination bucket is calculated as {prefix}-{region}"
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

  validation {
    condition     = contains(["CSV", "ORC", "Parquet"], var.output_format)
    error_message = "output_format must be one of: CSV, ORC, Parquet"
  }
}

variable "schedule_frequency" {
  description = "How often inventory reports are generated"
  type        = string
  default     = "Daily"

  validation {
    condition     = contains(["Daily", "Weekly"], var.schedule_frequency)
    error_message = "schedule_frequency must be one of: Daily, Weekly"
  }
}

variable "included_object_versions" {
  description = "Which object versions to include in inventory"
  type        = string
  default     = "All"

  validation {
    condition     = contains(["All", "Current"], var.included_object_versions)
    error_message = "included_object_versions must be one of: All, Current"
  }
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

  validation {
    condition     = contains(["true", "false"], var.test_mode)
    error_message = "test_mode must be 'true' or 'false'"
  }
}

variable "test_bucket_name" {
  description = "S3 bucket name to use for testing (only used when test_mode=true)"
  type        = string
  default     = ""
}

variable "exclude_bucket_prefixes" {
  description = "Comma-separated list of bucket name prefixes to exclude (e.g., 'aws-,cdk-,cf-templates-')"
  type        = string
  default     = ""
}

variable "exclude_bucket_tag" {
  description = "Tag key to check on buckets. If this tag exists with value 'true', the bucket is skipped"
  type        = string
  default     = "SkipInventory"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds (max 900 = 15 minutes)"
  type        = number
  default     = 900

  validation {
    condition     = var.lambda_timeout >= 60 && var.lambda_timeout <= 900
    error_message = "lambda_timeout must be between 60 and 900"
  }
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([7, 14, 30, 60, 90], var.log_retention_days)
    error_message = "log_retention_days must be one of: 7, 14, 30, 60, 90"
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
