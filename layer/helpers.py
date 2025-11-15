# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

import json, re, os
from dateutil.parser import parse as parse_dt
import boto3

# Re-use S3 client across invocations
s3 = boto3.client('s3')

# Patterns of critical files to monitor (from Lambda environment)
CRITICAL_FILE_PATTERNS = os.environ.get("CRITICAL_FILE_PATTERNS", "").split(",")

def is_critical(path: str) -> bool:
    """Return True if the path matches any declared critical pattern."""
    return any(re.match(p.strip(), path) for p in CRITICAL_FILE_PATTERNS if p.strip())

def load_file_metadata(bucket: str, key: str, version_id: str) -> dict:
    """Load and parse a specific SSM Inventory object version from S3."""
    obj = s3.get_object(Bucket=bucket, Key=key, VersionId=version_id)
    data = {}
    for line in obj['Body'].read().decode().splitlines():
        if line.strip():
            i = json.loads(line)
            n, d, m = i.get("Name","").strip(), i.get("InstalledDir","").strip(), i.get("ModificationTime","").strip()
            # Build absolute path → last modification timestamp map
            if n and d and m:
                data[f"{d.rstrip('/')}/{n}"] = m
    return data

def is_modified(path: str, current: dict, previous: dict) -> bool:
    """Return True if timestamps differ for that path."""
    try:
        return parse_dt(current[path]) != parse_dt(previous[path])
    except Exception:
        return current[path] != previous[path]

def extract_instance_id(bucket: str, key: str, version_id: str) -> str | None:
    """Extract EC2 instanceId from the SSM Inventory payload."""
    obj = s3.get_object(Bucket=bucket, Key=key, VersionId=version_id)
    for line in obj['Body'].read().decode().splitlines():
        if line.strip():
            r = json.loads(line)
            if "resourceId" in r:
                return r["resourceId"]
    return None