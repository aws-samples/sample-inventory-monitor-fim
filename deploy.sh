#!/bin/bash
set -e

# Validate AWS CLI is installed
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not found. Please install it first."; exit 1; }

if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <deployment-bucket> [stack-name] [options]"
    echo ""
    echo "Options:"
    echo "  --monitored-path    Path to monitor (default: /etc/paymentapp/)"
    echo "  --file-patterns     Regex patterns (default: ^/etc/paymentapp/config.*$)"
    echo "  --severity          Finding severity (default: MEDIUM)"
    echo "  --schedule          Collection schedule (default: rate(30 minutes))"
    echo "  --tag-key           EC2 tag key for inventory collection (default: FIM-Enabled)"
    echo "  --tag-value         EC2 tag value for inventory collection (default: true)"
    echo ""
    echo "Region: Uses AWS CLI default or set AWS_REGION or AWS_DEFAULT_REGION environment variable"
    exit 1
fi

DEPLOYMENT_BUCKET="$1"
STACK_NAME="${2:-SSMInventoryFIM}"

# Parse optional parameters
MONITORED_PATH="/etc/paymentapp/"
FILE_PATTERNS="^/etc/paymentapp/config.*$"
SEVERITY="MEDIUM"
SCHEDULE="rate(30 minutes)"
TAG_KEY="FIM-Enabled"
TAG_VALUE="true"

shift 2 2>/dev/null || shift 1
while [[ $# -gt 0 ]]; do
    case $1 in
        --monitored-path)
            MONITORED_PATH="$2"
            shift 2
            ;;
        --file-patterns)
            FILE_PATTERNS="$2"
            shift 2
            ;;
        --severity)
            SEVERITY="$2"
            shift 2
            ;;
        --schedule)
            SCHEDULE="$2"
            shift 2
            ;;
        --tag-key)
            TAG_KEY="$2"
            shift 2
            ;;
        --tag-value)
            TAG_VALUE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Region resolution order:
# 1. AWS_REGION environment variable (highest priority)
# 2. AWS_DEFAULT_REGION environment variable
# 3. AWS CLI default region configuration
# 4. us-east-1 (fallback default)
REGION="${AWS_REGION}"
if [ -z "$REGION" ]; then
    # Check AWS_DEFAULT_REGION if AWS_REGION is not set
    REGION="${AWS_DEFAULT_REGION}"
fi
if [ -z "$REGION" ]; then
    # Fall back to AWS CLI configuration
    REGION="$(aws configure get region)"
fi
if [ -z "$REGION" ] || [ "$REGION" = "None" ]; then
    # Final fallback to us-east-1
    REGION="us-east-1"
fi

echo "🚀 Deploying FIM Solution"
echo "Bucket: $DEPLOYMENT_BUCKET | Stack: $STACK_NAME | Region: ${REGION}"
echo ""

# Clean up old packages
rm -f fim-change-detector.zip helpers_layer.zip

echo "🔧 Packaging Lambda layer..."
rm -rf build
mkdir -p build/layer/python
cp layer/*.py build/layer/python/
[ -f layer/requirements.txt ] && python3 -m pip install -r layer/requirements.txt -t build/layer/python/ --quiet --disable-pip-version-check
cd build/layer && zip -r ../../helpers_layer.zip python/ -q && cd ../..

echo "� Packaginng Lambda function..."
zip -j fim-change-detector.zip lambda_function.py -q

echo "📤 Uploading to S3..."
aws s3 cp helpers_layer.zip "s3://$DEPLOYMENT_BUCKET/layer/helpers_layer.zip"
aws s3 cp fim-change-detector.zip "s3://$DEPLOYMENT_BUCKET/lambda/fim-change-detector.zip"

echo "☁️  Deploying CloudFormation stack..."
aws cloudformation deploy \
    --template-file template.yaml \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --parameter-overrides \
        DeploymentBucketName="$DEPLOYMENT_BUCKET" \
        MonitoredPath="$MONITORED_PATH" \
        CriticalFilePatterns="$FILE_PATTERNS" \
        FindingSeverity="$SEVERITY" \
        InventorySchedule="$SCHEDULE" \
        InventoryTagKey="$TAG_KEY" \
        InventoryTagValue="$TAG_VALUE" \
    --capabilities CAPABILITY_NAMED_IAM

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next: Launch EC2 with SSM role, create test file in $MONITORED_PATH, modify it to trigger finding"
echo "View outputs: aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].Outputs'"
