import boto3
import json
import os
from helper_functions import compare_inventory, create_securityhub_finding

ssm = boto3.client('ssm')
securityhub = boto3.client('securityhub')

def lambda_handler(event, context):
    # Example: FILE_PATTERNS="/etc/passwd,/etc/shadow"
    file_patterns = os.getenv("FILE_PATTERNS", "").split(",")
    severity = os.getenv("FINDING_SEVERITY", "MEDIUM")

    # Retrieve inventory data
    instance_id = event.get("InstanceId")
    response = ssm.list_inventory_entries(
        InstanceId=instance_id,
        TypeName="AWS:File"
    )
    files = response.get("Entries", [])

    # Compare snapshots (custom helper function)
    changes = compare_inventory(files, file_patterns)

    if changes:
        finding = create_securityhub_finding(instance_id, changes, severity)
        securityhub.batch_import_findings(Findings=[finding])

    return {
        "statusCode": 200,
        "body": json.dumps({"changes": changes})
    }
