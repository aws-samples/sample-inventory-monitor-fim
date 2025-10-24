import boto3, os, json, re
from datetime import datetime, UTC
from urllib.parse import unquote_plus
from helpers import is_critical, load_file_metadata, is_modified, extract_instance_id

s3 = boto3.client('s3')
securityhub = boto3.client('securityhub')

CRITICAL_FILE_PATTERNS = os.environ["CRITICAL_FILE_PATTERNS"].split(",")
SEVERITY_LABEL = os.environ["SEVERITY_LABEL"]

def lambda_handler(event, context):

    # Extract S3 event
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = unquote_plus(record['s3']['object']['key'])
    current_version = record['s3']['object'].get('versionId')
    if not current_version:
        return

    # Fetching the region name
    account_id = context.invoked_function_arn.split(":")[4]
    region = boto3.session.Session().region_name

    # Get object versions (latest first)
    versions = s3.list_object_versions(Bucket=bucket, Prefix=key).get('Versions', [])
    versions = sorted(versions, key=lambda v: v['LastModified'], reverse=True)

    # Find previous version
    idx = next((i for i,v in enumerate(versions) if v["VersionId"] == current_version), None)
    if idx is None or idx + 1 >= len(versions):
        return
    prev_version = versions[idx+1]["VersionId"]

    # Load both versions
    current = load_file_metadata(bucket, key, current_version)
    previous = load_file_metadata(bucket, key, prev_version)

    # Compare
    created = {p for p in set(current) - set(previous) if is_critical(p)}
    deleted = {p for p in set(previous) - set(current) if is_critical(p)}
    modified = {p for p in set(current) & set(previous) if is_modified(p, current, previous)}

    # Report if changes were found
    if created or deleted or modified:
        instance_id = extract_instance_id(bucket, key, current_version)
        now = datetime.now(UTC).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        finding = [{
            "SchemaVersion": "2018-10-08",
            "Id": f"fim-{instance_id}-{now}",
            "ProductArn": f"arn:aws:securityhub:{region}:{account_id}:product/{account_id}/default",
            "AwsAccountId": account_id,
            "GeneratorId": "ssm-inventory-fim",
            "CreatedAt": now,
            "UpdatedAt": now,
            "Types": ["Software and Configuration Checks/File Integrity Monitoring"],
            "Severity": {"Label": SEVERITY_LABEL},
            "Title": "File changes detected via SSM Inventory",
            "Description": (
                f"{len(created)} created, {len(modified)} modified, "
                f"{len(deleted)} deleted file(s) on instance {instance_id}"
            ),
            "Resources": [{"Type": "AwsEc2Instance", "Id": instance_id}]
        }]
        securityhub.batch_import_findings(Findings=finding)

    # No change – delete older S3 version
    else:
        if prev_version != current_version:
            try:
                s3.delete_object(Bucket=bucket, Key=key, VersionId=prev_version)
            except Exception as e:
                print(f"Delete previous S3 object version failed: {e}")