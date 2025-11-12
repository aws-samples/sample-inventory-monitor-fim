# sample-inventory-monitor-fim

> **⚠️ Note:** This is an implementation for demonstration purposes. It is a sample and not production-ready tool.

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

- [AWS Security Hub CSPM](https://aws.amazon.com/security-hub/cspm/) must be active in the target Region
- AWS CLI configured with appropriate credentials and valid region
- Python 3.9+ and pip installed
- S3 bucket for Lambda deployment packages
- VPC with at least 2 private subnets for Lambda deployment
- Follow least privilege: use a dedicated deployment role with permissions to create CloudFormation stacks, Lambda, IAM, S3, VPC, and SSM resources

**Note:** S3 bucket names must not exceed 63 characters. The template uses shortened names (`fim-inventory-` and `fim-logs-`) to accommodate long account IDs and region names.

**What Gets Deployed Automatically:**
- ✅ **S3 Logging Bucket** - Secure bucket for access logs with encryption and private access controls
- ✅ **S3 Inventory Bucket** - Versioned bucket with encryption, access logging, and private access controls
- ✅ **S3 Bucket Policy** - Enforces HTTPS-only access and grants SSM permissions
- ✅ **SSM Resource Data Sync** - Exports inventory data to S3
- ✅ **SSM Inventory Association** - Schedules file metadata collection from EC2 instances
- ✅ **Lambda Function & Layer** - Detects file changes with helper functions
- ✅ **Dead Letter Queue (SQS)** - Captures failed Lambda invocations
- ✅ **VPC Networking** - Private route table, security groups, and interface endpoints for Security Hub and SQS, plus S3 Gateway endpoint
- ✅ **IAM Resources** - Lambda execution role with managed policies
- ✅ **S3 Event Notification** - Triggers Lambda on new inventory data

### Deployment Steps

1. **Clone this repository:**
   ```bash
   git clone https://github.com/aws-samples/sample-inventory-monitor-fim.git
   cd sample-inventory-monitor-fim
   ```

2. **Run the deployment script:**
   ```bash
   chmod +x deploy.sh
   ./deploy.sh DEPLOYMENT-BUCKET
   ```

   The script will:
   - Package the Lambda Layer with helper functions and dependencies
   - Package the Lambda function code
   - Upload both packages to the deployment bucket
   - Deploy the CloudFormation stack to your AWS CLI configured region (creates S3 bucket, SSM resources, Lambda)
   
   **CloudFormation Stack Parameters:**
   The deployment accepts the following configurable parameters:
   - `DeploymentBucketName` (required) - S3 bucket for Lambda code packages
   - `VpcId` (required) - VPC ID where Lambda will be deployed
   - `PrivateSubnetIds` (required) - List of private subnet IDs (minimum 2)
   - `MonitoredPath` (optional) - File path to monitor (default: `/etc/paymentapp/`)
   - `CriticalFilePatterns` (optional) - Regex patterns for critical files (default: `^/etc/paymentapp/config.*$`)
   - `FindingSeverity` (optional) - Security Hub finding severity (default: `MEDIUM`)
   - `InventorySchedule` (optional) - Collection schedule (default: `rate(30 minutes)`)
   
   **Note:** The CloudFormation stack deploys to the region configured in your AWS CLI. To deploy to a different region, use:
   ```bash
   aws cloudformation deploy --region us-west-2 ...
   ```
   Or set the region before running the script:
   ```bash
   AWS_DEFAULT_REGION=us-west-2 ./deploy.sh DEPLOYMENT-BUCKET
   ```

   **Usage:**
   ```bash
   ./deploy.sh <deployment-bucket> [stack-name] [options]
   ```
   
   **Options (configure Lambda function behavior):**
   - `--monitored-path` - Which file path to monitor for file changes (default: `/etc/paymentapp/`)
   - `--file-patterns` - Regex patterns to identify critical files that trigger alerts (default: `^/etc/paymentapp/config.*$`)
   - `--severity` - Severity level for Security Hub findings (default: `MEDIUM`)
   - `--schedule` - How often to collect file metadata (default: `rate(30 minutes)`)

   **Examples:**
   
   Basic deployment:
   ```bash
   ./deploy.sh my-lambda-code-bucket
   ```
   
   Deploy to specific region:
   ```bash
   AWS_DEFAULT_REGION=us-west-2 ./deploy.sh my-lambda-code-bucket
   ```
   
   Custom configuration:
   ```bash
   ./deploy.sh my-lambda-code-bucket MyFimStack \
     --monitored-path /etc/ \
     --severity HIGH
   ```

### Verify Deployment

After deployment, verify the stack outputs:
```bash
aws cloudformation describe-stacks --stack-name InventoryMonitorFimSample --query 'Stacks[0].Outputs'
```

You should see all deployed resources including S3 buckets, SSM configurations, Lambda function with layer and DLQ, VPC networking, and security groups.

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
   - Add user data to create test file:
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
   aws cloudformation delete-stack --stack-name InventoryMonitorFimSample
   ```
4. **Clean up local files:**
   ```bash
   rm -rf build/ *.zip
   ```

Stack deletion automatically removes all deployed resources.  

## Security Enhancements

This CloudFormation template includes security and reliability features:

- **[Reserved Concurrency](https://docs.aws.amazon.com/lambda/latest/dg/configuration-concurrency.html)** - The Lambda function has `ReservedConcurrentExecutions: 10` to prevent runaway executions and control costs

- **[Dead Letter Queue (DLQ)](https://docs.aws.amazon.com/lambda/latest/dg/invocation-async.html#invocation-dlq)** - Failed Lambda invocations are sent to an SQS queue with 14-day retention for troubleshooting and replay

- **[VPC Deployment](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html)** - Lambda runs inside private subnets in a VPC for network isolation, with:
  - Private route table created automatically for VPC endpoint routing
  - S3 Gateway endpoint and interface endpoints for Security Hub and SQS to keep all network traffic private and avoid NAT Gateway costs
  - [Security groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-groups.html) restricting traffic to HTTPS only
  - No internet gateway dependency

- **[S3 Access Logging](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ServerLogs.html)** - The inventory bucket has server access logging enabled to track all requests for auditing and compliance purposes

- **[S3 HTTPS-Only Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html#transit)** - The S3 bucket policy enforces TLS/HTTPS for all connections using `aws:SecureTransport` condition, denying any HTTP requests

- **[S3 Private Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)** - The inventory bucket has `PublicAccessBlockConfiguration` enabled with all four settings to ensure complete privacy

- **[Managed IAM Policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_managed-vs-inline.html)** - Uses customer-managed IAM policies instead of inline policies for easier reuse, auditing, and centralized updates

### Additional Security Options

* **[Encrypt Lambda environment variables with a customer-managed KMS key](https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars.html#configuration-envvars-encryption)** - Use your own KMS key for full control over key rotation, audit access, and revocation

* **[Enable S3 Replication for compliance or disaster recovery](https://docs.aws.amazon.com/AmazonS3/latest/userguide/replication.html)** - Copy inventory data to another region or account for data redundancy and compliance

* **[Enable AWS CloudTrail Data Events for S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudtrail-logging-s3-info.html)** - CloudTrail data events log object-level actions on your inventory bucket, including user identity details for audits and investigations; configure this manually after deployment.

## License

This sample is licensed under the **MIT-0 License**. See [LICENSE](./LICENSE) for details.