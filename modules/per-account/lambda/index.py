import boto3
import json
import os
import time
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

# Configuration from environment variables
COLLECTOR_BUCKET_PREFIX = os.environ['COLLECTOR_BUCKET_PREFIX']
COLLECTOR_ACCOUNT_ID = os.environ['COLLECTOR_ACCOUNT_ID']
INVENTORY_NAME = os.environ['INVENTORY_NAME']
OUTPUT_FORMAT = os.environ['OUTPUT_FORMAT']
SCHEDULE_FREQUENCY = os.environ['SCHEDULE_FREQUENCY']
INCLUDED_OBJECT_VERSIONS = os.environ['INCLUDED_OBJECT_VERSIONS']
TEST_MODE = os.environ.get('TEST_MODE', 'false').lower() == 'true'
TEST_BUCKET_NAME = os.environ.get('TEST_BUCKET_NAME', '')
EXCLUDE_PREFIXES = [p.strip() for p in os.environ.get('EXCLUDE_BUCKET_PREFIXES', '').split(',') if p.strip()]
EXCLUDE_TAG = os.environ.get('EXCLUDE_BUCKET_TAG', '').strip()

# All optional fields matching the Terraform configuration
ALL_OPTIONAL_FIELDS = [
    'Size',
    'LastModifiedDate',
    'StorageClass',
    'ETag',
    'IsMultipartUploaded',
    'ReplicationStatus',
    'EncryptionStatus',
    'ObjectLockRetainUntilDate',
    'ObjectLockMode',
    'ObjectLockLegalHoldStatus',
    'IntelligentTieringAccessTier',
    'BucketKeyStatus',
    'ChecksumAlgorithm',
    'ObjectAccessControlList',
    'ObjectOwner',
    'ExpirationDate',
]


def get_bucket_region(bucket_name):
    """Get the region of an S3 bucket."""
    try:
        response = s3.get_bucket_location(Bucket=bucket_name)
        # None means us-east-1
        location = response.get('LocationConstraint')
        return location if location else 'us-east-1'
    except Exception as e:
        logger.error(f'Failed to get region for bucket {bucket_name}: {e}')
        return None


def should_skip_bucket(bucket_name):
    """Check if bucket should be excluded based on prefix or tag."""
    # Check prefix exclusions
    for prefix in EXCLUDE_PREFIXES:
        if bucket_name.startswith(prefix):
            logger.info(f'Skipping bucket {bucket_name} (matches prefix: {prefix})')
            return True

    # Check tag exclusion
    if EXCLUDE_TAG:
        try:
            tags = s3.get_bucket_tagging(Bucket=bucket_name)
            for tag in tags.get('TagSet', []):
                if tag['Key'] == EXCLUDE_TAG and tag['Value'].lower() == 'true':
                    logger.info(f'Skipping bucket {bucket_name} (tag: {EXCLUDE_TAG}=true)')
                    return True
        except s3.exceptions.from_code('NoSuchTagConfiguration'):
            pass  # No tags on bucket, that's fine
        except Exception:
            pass  # If we can't read tags, don't skip

    return False


def get_source_account_id():
    """Get current AWS account ID."""
    sts = boto3.client('sts')
    return sts.get_caller_identity()['Account']


def apply_inventory_config(bucket_name, bucket_region, source_account_id):
    """Apply S3 inventory configuration to a bucket."""
    destination_bucket = f'{COLLECTOR_BUCKET_PREFIX}-{bucket_region}'
    destination_arn = f'arn:aws:s3:::{destination_bucket}'

    inventory_config = {
        'Id': INVENTORY_NAME,
        'IsEnabled': True,
        'Destination': {
            'S3BucketDestination': {
                'Bucket': destination_arn,
                'Format': OUTPUT_FORMAT,
                'Prefix': source_account_id,
                'AccountId': COLLECTOR_ACCOUNT_ID,
            }
        },
        'Schedule': {
            'Frequency': SCHEDULE_FREQUENCY,
        },
        'IncludedObjectVersions': INCLUDED_OBJECT_VERSIONS,
        'OptionalFields': ALL_OPTIONAL_FIELDS,
    }

    # Use regional S3 client for the bucket
    regional_s3 = boto3.client('s3', region_name=bucket_region)
    regional_s3.put_bucket_inventory_configuration(
        Bucket=bucket_name,
        Id=INVENTORY_NAME,
        InventoryConfiguration=inventory_config,
    )

    return destination_bucket


def handler(event, context):
    """Main Lambda handler."""
    logger.info(f'Event: {json.dumps(event)}')
    source_account_id = get_source_account_id()
    logger.info(f'Source Account: {source_account_id}')
    logger.info(f'Collector Bucket Prefix: {COLLECTOR_BUCKET_PREFIX}')
    logger.info(f'Test Mode: {TEST_MODE}')

    results = {
        'account_id': source_account_id,
        'success': [],
        'failed': [],
        'skipped': [],
    }

    # Determine which buckets to process
    if TEST_MODE:
        if not TEST_BUCKET_NAME:
            logger.warning('Test mode enabled but no TEST_BUCKET_NAME set. Exiting.')
            return results
        buckets = [TEST_BUCKET_NAME]
        logger.info(f'TEST MODE: Processing only bucket: {TEST_BUCKET_NAME}')
    else:
        # Check if triggered by CreateBucket event
        if 'detail' in event and event.get('detail', {}).get('eventName') == 'CreateBucket':
            bucket_name = event['detail']['requestParameters']['bucketName']
            buckets = [bucket_name]
            logger.info(f'CreateBucket event: Processing new bucket: {bucket_name}')
        else:
            # Full discovery - list all buckets
            response = s3.list_buckets()
            buckets = [b['Name'] for b in response.get('Buckets', [])]
            logger.info(f'Discovered {len(buckets)} buckets in account')

    for bucket_name in buckets:
        try:
            # Check exclusions (skip in test mode)
            if not TEST_MODE and should_skip_bucket(bucket_name):
                results['skipped'].append(bucket_name)
                continue

            # Get bucket region
            bucket_region = get_bucket_region(bucket_name)
            if not bucket_region:
                results['failed'].append({
                    'bucket': bucket_name,
                    'error': 'Could not determine bucket region',
                })
                continue

            # Apply inventory config
            dest_bucket = apply_inventory_config(
                bucket_name, bucket_region, source_account_id
            )

            results['success'].append({
                'bucket': bucket_name,
                'region': bucket_region,
                'destination': dest_bucket,
            })
            logger.info(
                f'SUCCESS: {bucket_name} ({bucket_region}) -> {dest_bucket}'
            )

            # Throttle to avoid API rate limits
            time.sleep(0.1)

        except Exception as e:
            error_msg = str(e)
            results['failed'].append({
                'bucket': bucket_name,
                'error': error_msg,
            })
            logger.error(f'FAILED: {bucket_name} - {error_msg}')

    # Summary
    logger.info(
        f'SUMMARY: {len(results["success"])} success, '
        f'{len(results["failed"])} failed, '
        f'{len(results["skipped"])} skipped'
    )

    return results
