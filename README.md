# sample-inventory-monitor-fim

> **⚠️ Note:** This is an implementation for demonstration purposes. It is a sample and not production-ready tool. This sample is provided for non-production use only. Customers must review and meet their own security, regulatory, and compliance requirements before deployment.

## Overview

This sample demonstrates how to use **AWS Systems Manager (SSM) Inventory** to monitor file changes on Amazon EC2 instances, forward findings to **AWS Security Hub**, and store them in **Amazon Security Lake** for centralized analysis and visualization.  

The example focuses on **File Integrity Monitoring (FIM)**, but the same approach can be extended to monitor:  
- Installed applications  
- Network configurations  
- OS patches and updates  
- Custom inventory items  

## Architecture

![Architecture Diagram](res/architecture.png)

This sample solution uses the following AWS services:

- [AWS Systems Manager](https://aws.amazon.com/systems-manager/) Inventory collects file metadata from managed [Amazon EC2](https://aws.amazon.com/ec2/) instances
- [Amazon S3](https://aws.amazon.com/s3/) stores inventory snapshots via SSM Resource Data Sync with versioning enabled
- [Amazon S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html) trigger an [AWS Lambda](https://aws.amazon.com/lambda/) function when new inventory data arrives
- [AWS Lambda](https://aws.amazon.com/lambda/) function compares inventory snapshots to detect file changes (created, modified, deleted). A Lambda Layer provides reusable helper functions
- [AWS Security Hub](https://aws.amazon.com/security-hub/) receives findings in AWS Security Finding Format (ASFF)
- [Amazon Security Lake](https://aws.amazon.com/security-lake/) ingests findings in OCSF format for centralized analysis
- [Amazon Athena](https://aws.amazon.com/athena/) enables SQL queries on Security Lake data
- [Amazon QuickSight](https://aws.amazon.com/quicksight/) and [Amazon OpenSearch Service](https://aws.amazon.com/opensearch-service/) provide visualization and dashboarding capabilities

## Deployment

### Prerequisites

- [AWS Security Hub](https://aws.amazon.com/security-hub/) must be enabled in the target Region
- AWS CLI configured with appropriate credentials and valid region
- Python 3.9+ and pip installed
- S3 bucket for Lambda deployment packages
- Follow least privilege: use a dedicated deployment role with permissions to create CloudFormation stacks, Lambda, IAM, S3, and SSM resources

**What Gets Deployed Automatically:**
- ✅ **S3 Logging Bucket** - Versioned bucket with Object Lock (90-day GOVERNANCE retention) and explicit private ACL for immutable access logs
- ✅ **S3 Inventory Bucket** - Versioned bucket with encryption, access logging, and private access controls
- ✅ **S3 Bucket Policy** - Enforces HTTPS-only access and grants SSM permissions
- ✅ **SSM Resource Data Sync** - Exports inventory data to S3
- ✅ **SSM Inventory Association** - Schedules file metadata collection from EC2 instances
- ✅ **Lambda Function & Layer** - Serverless function with reserved concurrency (10) to detect file changes
- ✅ **Dead Letter Queue (SQS)** - Captures failed Lambda invocations with 14-day retention
- ✅ **IAM Resources** - Lambda execution role with customer-managed policies
- ✅ **S3 Event Notification** - Triggers Lambda on new inventory data (filtered to `AWS%3AFile/` prefix for file inventory objects only)

### Deployment Region

The deployment uses your AWS CLI default region, or you can override it with the `AWS_REGION` environment variable:

```bash
AWS_REGION=us-west-2 ./deploy.sh my-fim-deployment-bucket
```

### Deployment Steps

1. **Clone this repository:**
   ```bash
   git clone https://github.com/aws-samples/sample-inventory-monitor-fim.git
   cd sample-inventory-monitor-fim
   ```

2. **Create an S3 bucket for Lambda deployment packages:**
   ```bash
   aws s3 mb s3://my-fim-deployment-bucket
   ```
   
   Replace `my-fim-deployment-bucket` with your desired bucket name. This bucket is separate from the logging and inventory buckets created by CloudFormation and does not have Object Lock enabled.

3. **Run the deployment script:**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh my-fim-deployment-bucket
   ```

   Replace `my-fim-deployment-bucket` with the bucket name you created in step 2. The script packages the Lambda code, uploads it to S3, and calls CloudFormation to deploy all resources including Lambda, S3 buckets, and SSM configurations.
   
   **Usage:**
   ```bash
   ./deploy.sh <deployment-bucket> [stack-name] [options]
   ```
   
   The `stack-name` parameter is optional and defaults to `SSMInventoryFIM`.
   
   **Configuration Options:**
   
   All options are optional and allow you to customize the Lambda function behavior:
   
   | Option | Description | Default Value |
   |--------|-------------|---------------|
   | `--monitored-path` | File system path to monitor for changes | `/etc/paymentapp/` |
   | `--file-patterns` | Regex patterns to identify critical files that trigger alerts | `^/etc/paymentapp/config.*$` |
   | `--severity` | Severity level for Security Hub findings (INFORMATIONAL, LOW, MEDIUM, HIGH, CRITICAL) | `MEDIUM` |
   | `--schedule` | How often to collect file metadata from EC2 instances | `rate(30 minutes)` |
   | `--tag-key` | EC2 tag key to identify instances for inventory collection | `FIM-Enabled` |
   | `--tag-value` | EC2 tag value to identify instances for inventory collection | `true` |

   **Examples:**
   
   Basic deployment with default settings:
   ```bash
   ./deploy.sh my-fim-deployment-bucket
   ```

   Custom configuration with options:
   ```bash
   ./deploy.sh my-fim-deployment-bucket MyFimStack \
     --monitored-path /etc/ \
     --severity HIGH \
     --schedule "rate(15 minutes)"
   ```
   
### Verify Deployment

After deployment, verify the stack outputs:
```bash
aws cloudformation describe-stacks --stack-name SSMInventoryFIM --query 'Stacks[0].Outputs'
```

You should see all deployed resources including S3 buckets, SSM configurations, Lambda function with layer and DLQ.

## Testing the Solution

### Step 1: Launch EC2 Instance

1. **Create IAM role for EC2:**
   - Go to IAM → Roles → Create role
   - Choose AWS Service → EC2
   - Attach `AmazonSSMManagedInstanceCore` policy
   - Name it `SSMAccessRole`

2. **Launch EC2 instance:**
   - Use Amazon Linux 2 AMI (t3.micro for testing)
   - Under Advanced details → IAM instance profile, select `SSMAccessRole`
   - **Important:** Add a tag with the key and value you configured during deployment (default: `FIM-Enabled=true`). Only EC2 instances with this tag are targeted by the SSM Inventory Association for file monitoring.
   - Add User data section (creates a test file):
     ```bash
     #!/bin/bash
     mkdir -p /etc/paymentapp
     echo "db_password=initial123" > /etc/paymentapp/config.yaml
     ```
   - Launch instance

### Step 2: Wait for Inventory Collection

The SSM Inventory Association runs on the schedule you configured (default: every 30 minutes).

**To manually trigger inventory collection:**
1. Go to Systems Manager → State Manager
2. Select your association (name: `<StackName>-file-inventory`)
3. Click Apply association now
4. Wait for status to show Success

### Step 3: Simulate File Change

1. Connect to EC2 instance via Systems Manager Session Manager
2. Modify the test file:
   ```bash
   echo "db_password=hacked456" | sudo tee /etc/paymentapp/config.yaml
   ```
3. Trigger inventory collection again (or wait for next scheduled run)

### Step 4: Verify Finding

**Check Security Hub:**
- Go to [Security Hub CSPM](https://aws.amazon.com/security-hub/cspm/) → Findings
- Look for finding with title: "File changes detected via SSM Inventory"

**Note:** Security Hub findings may take a few minutes to appear after the Lambda function runs.


## Amazon Security Lake Integration (Optional)

Amazon Security Lake automatically collects and normalizes findings from AWS Security Hub into OCSF format. Once enabled with Security Hub as a data source, all FIM findings are ingested without code changes. Query data with Amazon Athena and visualize with Amazon QuickSight or Amazon OpenSearch Service.

**Note:** Security Lake processes findings before they appear in Athena, so expect a short delay between ingestion and data availability. 

## Project Structure

```
.
├── lambda_function.py          # Main Lambda handler
├── layer/
│   ├── helpers.py             # Helper functions for FIM logic
│   └── requirements.txt       # Python dependencies (python-dateutil)
├── deploy.sh                  # Automated deployment script
├── template.yaml              # CloudFormation template
├── res/
│   └── architecture.png       # Architecture diagram
└── README.md                  # This file
```

## Cleanup

To remove all resources and avoid ongoing costs:

1. **Terminate EC2 test instances**
2. **Empty/delete the inventory S3 bucket**
3. **Delete the CloudFormation stack:**
   ```bash
   aws cloudformation delete-stack --stack-name SSMInventoryFIM
   ```
4. **Clean up local files:**
   ```bash
   rm -rf build/ *.zip
   ```

Stack deletion automatically removes all deployed resources.  

## Security Enhancements

This CloudFormation template includes security and reliability features:

- **[Reserved Concurrency](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)** - Lambda function limited to 10 concurrent executions to prevent runaway costs (CKV_AWS_115 compliant)

- **[Dead Letter Queue (DLQ)](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html#invocation-dlq)** - Failed invocations sent to SQS with 14-day retention for troubleshooting

- **[S3 Explicit Private ACL](https://docs.aws.amazon.com/AmazonS3/latest/userguide/acl-overview.html)** - Logging bucket has explicit `AccessControl: Private` with `BucketOwnerPreferred` ownership (S3_BUCKET_NO_PUBLIC_RW_ACL compliant)

- **[S3 Access Logging](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html)** - Inventory bucket logs all access requests; logging bucket protected by versioning, Object Lock, and CloudTrail

- **[S3 HTTPS-Only Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html#transit)** - Bucket policies enforce TLS/HTTPS using `aws:SecureTransport` condition

- **[S3 Private Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)** - All buckets have `PublicAccessBlockConfiguration` enabled

- **[Customer-Managed IAM Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html)** - Dedicated managed policies for easier reuse and centralized updates

- **[S3 Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)** - All buckets have versioning enabled to preserve historical versions

- **[S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)** - Logging bucket uses GOVERNANCE mode (90-day retention) for immutable audit logs

### Additional Security Options

* **[VPC Deployment](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)** - For enhanced network isolation, deploy Lambda in private subnets with VPC endpoints for S3, Security Hub, and SQS. This adds operational complexity but provides additional network-level security controls.

* **[Encrypt Lambda environment variables with a customer-managed KMS key](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html#configuration-envvars-encryption)** - Use your own KMS key for full control over key rotation and access

* **[Enable S3 Replication for compliance or disaster recovery](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)** - Copy inventory data to another region or account for redundancy

* **[Enable AWS CloudTrail Data Events for S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudtrail-logging-s3-info.html)** - Log object-level actions with user identity details for audits

## License

This sample is licensed under the **MIT-0 License**. See [LICENSE](./LICENSE) for details.
