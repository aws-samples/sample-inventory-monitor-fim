import datetime

def compare_inventory(files, patterns):
    """Return list of files from inventory that match patterns and changed."""
    changes = []
    for f in files:
        path = f.get("Path")
        if any(path.endswith(p.strip()) for p in patterns if p):
            changes.append(f)
    return changes

def create_securityhub_finding(instance_id, changes, severity):
    """Create a Security Hub finding object."""
    now = datetime.datetime.utcnow().replace(tzinfo=datetime.timezone.utc).isoformat()
    return {
        "SchemaVersion": "2018-10-08",
        "Id": f"{instance_id}/fim/{now}",
        "ProductArn": f"arn:aws:securityhub:::product/aws/securityhub",
        "GeneratorId": "InventoryMonitorFimSample",
        "AwsAccountId": "PLACEHOLDER-ACCOUNT-ID",
        "Types": ["Software and Configuration Checks/File Integrity Monitoring"],
        "CreatedAt": now,
        "UpdatedAt": now,
        "Severity": {"Label": severity},
        "Title": f"File integrity change detected on {instance_id}",
        "Description": f"Detected changes in {len(changes)} monitored files.",
        "Resources": [
            {"Type": "AwsEc2Instance", "Id": instance_id}
        ],
        "RecordState": "ACTIVE"
    }
