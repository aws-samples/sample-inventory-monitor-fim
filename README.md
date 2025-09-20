# InventoryMonitorFimSample

This repository contains a sample solution from the AWS Security Blog:  
**File Integrity Monitoring with AWS Systems Manager and Amazon Security Lake**

## Overview

The provided sample demonstrates how to use **AWS Systems Manager (SSM) Inventory** to monitor file changes on EC2 instances, send findings to **AWS Security Hub**, and store them in **Amazon Security Lake** for centralized analysis.

In this sample, File Integrity Monitoring (FIM) is the example use case.  
However, the same approach can be **extended to other scenarios** where you want to track and analyze inventory changes, such as:
- Installed applications
- Network configurations
- OS patches and updates
- Custom inventory items

## Architecture

- **SSM Inventory** collects metadata and file information from managed EC2 instances.  
- **Lambda function** compares inventory snapshots to detect changes.  
- **Lambda Layer** contains reusable helper functions.  
- **Security Hub** aggregates findings.  
- **Amazon Security Lake** stores and analyzes security data.  

## Deployment

You can deploy this solution with **one click** using the included CloudFormation template.

### Prerequisites
- An AWS account with permissions to create IAM roles, Lambda, and S3 buckets.
- Security Hub and Security Lake enabled in your Region.
- At least one EC2 instance managed by SSM.

### Steps
1. Clone this repository:
   ```bash
   git clone <repo-url>
   cd InventoryMonitorFimSample
   ```

2. Deploy the CloudFormation stack:
   ```bash
   aws cloudformation deploy      --template-file template.yaml      --stack-name InventoryMonitorFimSample      --capabilities CAPABILITY_NAMED_IAM
   ```

3. After deployment, verify:
   - The Lambda function is created with its Layer.
   - Findings appear in **Security Hub**.
   - Security data flows into **Amazon Security Lake**.

### Cleanup
To avoid ongoing costs, delete all created resources:
- Delete the CloudFormation stack:
  ```bash
  aws cloudformation delete-stack --stack-name InventoryMonitorFimSample
  ```
- Terminate EC2 instances used for testing.
- Delete Security Lake S3 buckets if no longer required.

## Blog Reference
For full context, explanation, and screenshots, see the AWS Security Blog post:  
👉 [File Integrity Monitoring with AWS Systems Manager and Amazon Security Lake](<insert-blog-link-here>)
