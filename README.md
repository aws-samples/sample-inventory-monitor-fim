# sample-inventory-monitor-fim

This repository contains a sample implementation from the AWS Security Blog:  
**File Integrity Monitoring with AWS Systems Manager and Amazon Security Lake**  

👉 Blog reference: [File Integrity Monitoring with AWS Systems Manager and Amazon Security Lake](<insert-blog-link-here>)  

---

## Overview

This sample demonstrates how to use **AWS Systems Manager (SSM) Inventory** to monitor file changes on Amazon EC2 instances, forward findings to **AWS Security Hub**, and store them in **Amazon Security Lake** for centralized analysis and visualization.  

The example focuses on **File Integrity Monitoring (FIM)**, but the same approach can be extended to monitor:  
- Installed applications  
- Network configurations  
- OS patches and updates  
- Custom inventory items  

---

## Architecture

- **SSM Inventory** collects metadata and file information from managed EC2 instances.  
- **Amazon S3** stores inventory snapshots (via SSM Resource Data Sync, versioned).  
- **Amazon S3 Event Notifications** trigger a **Lambda function**.  
- **Lambda function** compares the latest snapshot with the previous one and generates findings.  
- **Lambda Layer** provides reusable helper functions.  
- **AWS Security Hub** aggregates findings.  
- **Amazon Security Lake** ingests findings in OCSF format for querying with Athena or dashboards in QuickSight/OpenSearch.  

---

## Deployment

You can deploy this solution with **one click** using the included **CloudFormation template** (`template.yaml`).  

### Prerequisites
- An AWS account with permissions to create IAM roles, Lambda, S3 buckets, and Security Hub integrations.  
- **Security Hub** and **Security Lake** enabled in your Region.  
- At least one **EC2 instance managed by SSM** (see [Testing with EC2](#testing-with-ec2)).  

---

### Steps

1. Clone this repository:
   ```bash
   git clone https://github.com/aws-samples/sample-inventory-monitor-fim.git
   cd sample-inventory-monitor-fim
   ```

2. Deploy the CloudFormation stack:
   ```bash
   aws cloudformation deploy      --template-file template.yaml      --stack-name InventoryMonitorFimSample      --capabilities CAPABILITY_NAMED_IAM
   ```

3. After deployment, verify:  
   - The Lambda function and Layer are created.  
   - Environment variables are set (see [Configuration](#configuration)).  
   - Findings appear in **Security Hub**.  
   - Security data flows into **Amazon Security Lake**.  

---

## Testing with EC2

This sample does not create EC2 instances. To test file integrity monitoring, follow these steps:  

1. **Create an IAM role for EC2**  
   - Go to IAM → Roles → Create role.  
   - Choose **AWS Service → EC2**.  
   - Attach `AmazonSSMManagedInstanceCore`.  
   - Name it `SSMAccessRole`.  

2. **Launch an EC2 instance**  
   - Use Amazon Linux 2 AMI (t3.micro works for testing).  
   - Under *Advanced details → IAM instance profile*, select `SSMAccessRole`.  
   - Add user data to create a sample file:  
     ```bash
     #!/bin/bash
     mkdir -p /etc/paymentapp
     echo "db_password=initial123" > /etc/paymentapp/config.yaml
     ```

3. **Enable SSM Inventory**  
   - In Systems Manager, set up Inventory collection for file metadata.  
   - Limit the path to `/etc/paymentapp/`.  
   - Create a Resource Data Sync to a versioned S3 bucket.  

4. **Simulate a file change**  
   - Use Systems Manager Session Manager to connect to the EC2 instance.  
   - Run:  
     ```bash
     echo "db_password=hacked456" | sudo tee /etc/paymentapp/config.yaml
     ```  
   - The next inventory run will detect the change, trigger the Lambda, and create a finding in **Security Hub**.  

---

## Configuration

The Lambda function is configured with environment variables (see `template.yaml`):  

- **`FILE_PATTERNS`**: Comma-separated list of file paths to monitor.  
  Example default:  
  ```
  /etc/passwd,/etc/shadow
  ```
- **`FINDING_SEVERITY`**: Severity label for Security Hub findings.  
  Example default:  
  ```
  MEDIUM
  ```

You can adjust these values in the Lambda console or by updating the CloudFormation template.  

---

## Cleanup

To avoid ongoing costs, delete all created resources:  

```bash
aws cloudformation delete-stack --stack-name InventoryMonitorFimSample
```

Also remove:  
- EC2 instances used for testing.  
- Resource Data Syncs and SSM Inventory associations.  
- Security Lake data stores and Security Hub findings (if no longer needed).  

---

## License

This sample is licensed under the **Apache 2.0 License**. See [LICENSE](./LICENSE) for details.  
