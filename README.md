# S3 Inventory StackSet (Terraform)

Terraform replacement for the CloudFormation StackSet-based S3 inventory deployment. Deploys a Lambda function per AWS account that **auto-discovers all S3 buckets** and applies inventory configurations pointing to regional collector buckets.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  GitHub Actions                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐                  │
│  │ Account A│    │ Account B│    │ Account N│   (parallel)      │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘                  │
│       │               │               │                         │
│       ▼               ▼               ▼                         │
│  OIDC Auth → Terraform Plan → Terraform Apply                   │
└─────────────────────────────────────────────────────────────────┘
                        │
        Per account deploys:
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
  ┌──────────┐   ┌────────────┐  ┌────────────┐
  │  Lambda   │   │ EventBridge│  │ EventBridge│
  │  Function │◄──│ Daily Rule │  │ CreateBkt  │
  │           │◄──│            │  │   Rule     │
  └─────┬─────┘   └────────────┘  └────────────┘
        │
        ▼
  Discovers all S3 buckets
  Applies inventory config → Regional collector bucket
```

### How It Works

1. **Lambda discovers buckets at runtime** — no bucket list needed
2. **Daily EventBridge schedule** triggers full discovery across all buckets in the account
3. **CreateBucket EventBridge rule** auto-configures new buckets via CloudTrail events
4. **Exclusion logic** skips buckets by name prefix or tag (`SkipInventory=true`)
5. **Test mode** validates against a single bucket before full rollout

### Resources Created (per account)

| Resource | Name | Purpose |
|----------|------|---------|
| Lambda Function | `s3-inventory-config` | Discovers buckets, applies inventory configs |
| IAM Role | `s3-inventory-config-lambda-role-{region}` | Lambda execution role with S3 + CloudWatch permissions |
| CloudWatch Log Group | `/aws/lambda/s3-inventory-config` | Lambda logs (configurable retention) |
| EventBridge Rule | `s3-inventory-daily-trigger` | Daily scheduled full discovery |
| EventBridge Rule | `s3-inventory-new-bucket-trigger` | Reacts to new bucket creation via CloudTrail |

## Prerequisites

Per target account:

- **OIDC role** (e.g., `NxGitHubActionsRole`) with permissions to manage Lambda, IAM, EventBridge, CloudWatch
- **Terraform state bucket** for remote state storage
- **CloudTrail enabled** — required for the CreateBucket event detection

## Quick Start

### 1. Configure shared defaults

Edit `terraform.tfvars` with your collector account and preferences:

```hcl
collector_bucket_prefix  = "nvisionx-s3-inventory"
collector_account_id     = "000000000000"    # Account hosting collector buckets
inventory_name           = "terra-s3-inv"
output_format            = "Parquet"
schedule_frequency       = "Daily"
exclude_bucket_prefixes  = "aws-,cdk-,cf-templates-"
exclude_bucket_tag       = "SkipInventory"
```

### 2. Add accounts

Edit `accounts.json` — one entry per AWS account:

```json
{
  "accounts": [
    {
      "account_id": "111111111111",
      "oidc_role": "NxGitHubActionsRole",
      "aws_region": "us-east-1",
      "terraform_backend": {
        "bucket": "your-tf-state-bucket",
        "key": "s3-inventory-stackset/terraform.tfstate",
        "region": "us-east-1",
        "encrypt": true,
        "use_lockfile": true
      },
      "overrides": {}
    }
  ]
}
```

Each account gets its own Terraform state via the `terraform_backend` block.

### 3. Deploy

**Option A — Push to main** (auto-deploys all accounts):
```bash
git push origin main
```

**Option B — Manual trigger** (from any branch):

Go to **Actions → Deploy S3 Inventory (Plan + Apply) → Run workflow** → select branch.

### 4. Verify

Check CloudWatch logs for the Lambda's `SUMMARY` line:
```
SUMMARY: 42 success, 0 failed, 3 skipped
```

## Per-Account Overrides

Use the `overrides` field in `accounts.json` to customize parameters per account. Any variable from `variables.tf` can be overridden:

```json
"overrides": {
  "test_mode": "true",
  "test_bucket_name": "my-test-bucket",
  "schedule_expression": "rate(7 days)",
  "exclude_bucket_prefixes": "aws-,cdk-,cf-templates-,tmp-"
}
```

### Test Mode

Deploy in test mode first to validate a single bucket before full rollout:

```json
"overrides": {
  "test_mode": "true",
  "test_bucket_name": "some-bucket-in-the-account"
}
```

Once verified, remove the overrides to enable full discovery:

```json
"overrides": {}
```

## Configuration Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `collector_bucket_prefix` | `nvisionx-s3-inventory` | Prefix for regional collector buckets (`{prefix}-{region}`) |
| `collector_account_id` | *(required)* | AWS account ID hosting collector buckets |
| `inventory_name` | `terra-s3-inv` | Inventory configuration ID applied to each bucket |
| `output_format` | `Parquet` | Output format: `CSV`, `ORC`, or `Parquet` |
| `schedule_frequency` | `Daily` | Inventory report frequency: `Daily` or `Weekly` |
| `included_object_versions` | `All` | Object versions: `All` or `Current` |
| `schedule_expression` | `rate(1 day)` | EventBridge schedule for full discovery |
| `test_mode` | `false` | Process only `test_bucket_name` when `true` |
| `test_bucket_name` | `""` | Bucket to target in test mode |
| `exclude_bucket_prefixes` | `""` | Comma-separated prefixes to skip (e.g., `aws-,cdk-`) |
| `exclude_bucket_tag` | `SkipInventory` | Skip buckets with this tag set to `true` |
| `lambda_timeout` | `900` | Lambda timeout in seconds (60–900) |
| `log_retention_days` | `30` | CloudWatch log retention (7, 14, 30, 60, or 90) |

## Inventory Optional Fields

All available S3 inventory fields are included in the configuration:

`Size`, `LastModifiedDate`, `StorageClass`, `ETag`, `IsMultipartUploaded`, `ReplicationStatus`, `EncryptionStatus`, `ObjectLockRetainUntilDate`, `ObjectLockMode`, `ObjectLockLegalHoldStatus`, `IntelligentTieringAccessTier`, `BucketKeyStatus`, `ChecksumAlgorithm`, `ObjectAccessControlList`, `ObjectOwner`, `LifecycleExpirationDate`

## Migration from CloudFormation StackSet

Resources are named identically between CFN and Terraform, so you have two migration paths:

**Option A — Clean deploy:** Delete the CFN stack instance first, then deploy Terraform.

**Option B — Import existing resources:**

```bash
terraform import 'module.s3_inventory_per_account.aws_lambda_function.s3_inventory' s3-inventory-config
terraform import 'module.s3_inventory_per_account.aws_iam_role.lambda_role' s3-inventory-config-lambda-role-us-east-1
terraform import 'module.s3_inventory_per_account.aws_cloudwatch_log_group.lambda_logs' /aws/lambda/s3-inventory-config
terraform import 'module.s3_inventory_per_account.aws_cloudwatch_event_rule.scheduled' s3-inventory-daily-trigger
terraform import 'module.s3_inventory_per_account.aws_cloudwatch_event_rule.create_bucket' s3-inventory-new-bucket-trigger
```

Both approaches can coexist temporarily — `PutInventoryConfiguration` is idempotent.

## Project Structure

```
s3-inventory-stackset-tf/
├── modules/
│   └── per-account/
│       ├── main.tf              # Lambda + IAM + EventBridge + CloudWatch
│       ├── variables.tf         # 13 configurable variables + tags
│       ├── outputs.tf           # Lambda ARN, role ARN, log group
│       └── lambda/
│           └── index.py         # Auto-discovery Lambda (Python 3.12)
├── main.tf                      # Root module (S3 backend, provider, module call)
├── variables.tf                 # Pass-through variables + aws_region
├── outputs.tf                   # Pass-through outputs
├── terraform.tfvars             # Shared defaults
├── accounts.json                # Multi-account config
├── .github/
│   └── workflows/
│       ├── deploy.yml           # Push to main or manual → plan + apply
│       └── plan.yml             # PR or manual → plan only
├── .gitignore
└── README.md
```
