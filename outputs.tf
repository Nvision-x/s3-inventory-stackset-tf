output "lambda_function_arn" {
  description = "ARN of the S3 inventory configuration Lambda function"
  value       = module.s3_inventory_per_account.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.s3_inventory_per_account.lambda_function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.s3_inventory_per_account.lambda_role_arn
}

output "log_group_name" {
  description = "CloudWatch log group for Lambda function"
  value       = module.s3_inventory_per_account.log_group_name
}

output "test_mode" {
  description = "Whether test mode is enabled"
  value       = module.s3_inventory_per_account.test_mode
}

output "test_bucket" {
  description = "Bucket being used for testing"
  value       = module.s3_inventory_per_account.test_bucket
}
