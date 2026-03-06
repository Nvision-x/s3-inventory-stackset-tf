data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ------------------------------------------------------
# Lambda package
# ------------------------------------------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda/index.zip"
}

# ------------------------------------------------------
# 1. IAM Role + Policy
# ------------------------------------------------------
resource "aws_iam_role" "lambda_role" {
  name = "s3-inventory-config-lambda-role-${data.aws_region.current.name}"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "S3InventoryConfigPolicy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketDiscovery"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3InventoryConfig"
        Effect = "Allow"
        Action = [
          "s3:PutInventoryConfiguration",
          "s3:GetInventoryConfiguration",
          "s3:DeleteInventoryConfiguration"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "S3TagRead"
        Effect = "Allow"
        Action = [
          "s3:GetBucketTagging"
        ]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}

# ------------------------------------------------------
# 2. Lambda Function
# ------------------------------------------------------
resource "aws_lambda_function" "s3_inventory" {
  function_name    = "s3-inventory-config"
  description      = "Discovers S3 buckets and applies inventory configurations to regional collector buckets"
  runtime          = "python3.12"
  handler          = "index.handler"
  role             = aws_iam_role.lambda_role.arn
  timeout          = var.lambda_timeout
  memory_size      = 256
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  tags             = var.tags

  environment {
    variables = {
      COLLECTOR_BUCKET_PREFIX  = var.collector_bucket_prefix
      COLLECTOR_ACCOUNT_ID     = var.collector_account_id
      INVENTORY_NAME           = var.inventory_name
      OUTPUT_FORMAT            = var.output_format
      SCHEDULE_FREQUENCY       = var.schedule_frequency
      INCLUDED_OBJECT_VERSIONS = var.included_object_versions
      TEST_MODE                = var.test_mode
      TEST_BUCKET_NAME         = var.test_bucket_name
      EXCLUDE_BUCKET_PREFIXES  = var.exclude_bucket_prefixes
      EXCLUDE_BUCKET_TAG       = var.exclude_bucket_tag
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# ------------------------------------------------------
# 3. CloudWatch Log Group
# ------------------------------------------------------
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/s3-inventory-config"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ------------------------------------------------------
# 4. EventBridge Rule - Scheduled (Daily)
# ------------------------------------------------------
resource "aws_cloudwatch_event_rule" "scheduled" {
  name                = "s3-inventory-daily-trigger"
  description         = "Triggers S3 inventory Lambda daily to discover and configure all buckets"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "scheduled_target" {
  rule      = aws_cloudwatch_event_rule.scheduled.name
  target_id = "S3InventoryDailyTarget"
  arn       = aws_lambda_function.s3_inventory.arn
  input     = jsonencode({ source = "scheduled" })
}

resource "aws_lambda_permission" "allow_scheduled_event" {
  statement_id  = "AllowScheduledEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_inventory.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled.arn
}

# ------------------------------------------------------
# 5. EventBridge Rule - CreateBucket event
# ------------------------------------------------------
resource "aws_cloudwatch_event_rule" "create_bucket" {
  name        = "s3-inventory-new-bucket-trigger"
  description = "Triggers S3 inventory Lambda when a new bucket is created"
  tags        = var.tags

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["s3.amazonaws.com"]
      eventName   = ["CreateBucket"]
    }
  })
}

resource "aws_cloudwatch_event_target" "create_bucket_target" {
  rule      = aws_cloudwatch_event_rule.create_bucket.name
  target_id = "S3InventoryNewBucketTarget"
  arn       = aws_lambda_function.s3_inventory.arn
}

resource "aws_lambda_permission" "allow_create_bucket_event" {
  statement_id  = "AllowCreateBucketEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_inventory.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.create_bucket.arn
}
