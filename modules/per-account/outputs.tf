output "lambda_function_arn" {
  description = "ARN of the S3 inventory configuration Lambda function"
  value       = aws_lambda_function.s3_inventory.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.s3_inventory.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "log_group_name" {
  description = "CloudWatch log group for Lambda function"
  value       = aws_cloudwatch_log_group.lambda_logs.name
}

output "test_mode" {
  description = "Whether test mode is enabled"
  value       = var.test_mode
}

output "test_bucket" {
  description = "Bucket being used for testing"
  value       = var.test_bucket_name
}
