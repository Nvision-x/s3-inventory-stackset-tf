# S3 Inventory StackSet (Terraform)

Terraform replacement for the CloudFormation StackSet-based S3 inventory deployment. Deploys a Lambda function per AWS account that **auto-discovers** all S3 buckets and applies inventory configurations pointing to regional collector buckets.

## How It Works

1. **Lambda discovers buckets at runtime** — no bucket list needed
2. **Daily EventBridge schedule** triggers full discovery across all buckets
3. **CreateBucket EventBridge rule** auto-configures new buckets via CloudTrail events
4. **Exclusion logic** skips buckets by name prefix or tag (`SkipInventory=true`)
5. **Test mode** lets you validate against a single bucket before full rollout

## Adding an Account

Add an entry to `accounts.json`:

```json
{
  "account_id": "123456789012",
  "oidc_role": "NxGitHubActionsRole",
  "aws_region": "us-east-1",
  "terraform_backend": {
    "bucket": "tf-state-bucket",
    "key": "s3-inventory-stackset/terraform.tfstate",
    "region": "us-east-2",
    "encrypt": true,
    "use_lockfile": true
  },
  "overrides": {}
}
```

Use `overrides` for per-account parameter differences (e.g., test mode):

```json
"overrides": {
  "test_mode": "true",
  "test_bucket_name": "my-test-bucket"
}
```

## Prerequisites

Per target account:
- **OIDC role** (e.g., `NxGitHubActionsRole`) with permissions to manage Lambda, IAM, EventBridge, CloudWatch
- **S3 backend bucket** for Terraform state
- **CloudTrail** enabled (required for CreateBucket event detection)

## Migration from CloudFormation StackSet

Resources are named identically between CFN and Terraform:
- Lambda: `s3-inventory-config`
- IAM Role: `s3-inventory-config-lambda-role-{region}`
- EventBridge rules: `s3-inventory-daily-trigger`, `s3-inventory-new-bucket-trigger`

**Option A — Clean deploy:** Delete CFN stack instance first, then deploy Terraform.

**Option B — Import:** Use `terraform import` to adopt existing resources:
```bash
terraform import 'module.s3_inventory_per_account.aws_lambda_function.s3_inventory' s3-inventory-config
terraform import 'module.s3_inventory_per_account.aws_iam_role.lambda_role' s3-inventory-config-lambda-role-us-east-1
terraform import 'module.s3_inventory_per_account.aws_cloudwatch_log_group.lambda_logs' /aws/lambda/s3-inventory-config
terraform import 'module.s3_inventory_per_account.aws_cloudwatch_event_rule.scheduled' s3-inventory-daily-trigger
terraform import 'module.s3_inventory_per_account.aws_cloudwatch_event_rule.create_bucket' s3-inventory-new-bucket-trigger
```

Both can coexist temporarily — `PutInventoryConfiguration` is idempotent.

## Verification

1. Deploy with `test_mode: "true"` + `test_bucket_name` in overrides
2. Check CloudWatch logs for `SUMMARY` line
3. Switch to full mode (remove overrides) and redeploy
4. Create a new S3 bucket — verify EventBridge triggers Lambda
