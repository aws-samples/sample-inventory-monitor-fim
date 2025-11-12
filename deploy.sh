#!/bin/bash
set -e

# Check required parameters
if [ -z "$1" ]; then
    echo "❌ Error: Deployment bucket name is required"
    echo ""
    echo "Usage: ./deploy.sh <deployment-bucket> [stack-name] [options]"
    echo ""
    echo "Parameters:"
    echo "  deployment-bucket      (Required) S3 bucket for Lambda code/layer packages"
    echo "  stack-name             (Optional) CloudFormation stack name (default: InventoryMonitorFimSample)"
    echo ""
    echo "Options (passed as CloudFormation parameters):"
    echo "  --monitored-path       Path to monitor (default: /etc/paymentapp/)"
    echo "  --file-patterns        Regex patterns for critical files (default: ^/etc/paymentapp/config.*$)"
    echo "  --severity             Finding severity (default: MEDIUM)"
    echo "  --schedule             Inventory schedule (default: rate(30 minutes))"
    echo ""
    echo "Note: The solution will be deployed to your default AWS CLI region."
    echo "      Set AWS_DEFAULT_REGION environment variable to change the region."
    echo ""
    echo "Examples:"
    echo "  ./deploy.sh my-deployment-bucket"
    echo "  AWS_DEFAULT_REGION=us-west-2 ./deploy.sh my-deployment-bucket MyFimStack --monitored-path /etc/ --severity HIGH"
    exit 1
fi

DEPLOYMENT_BUCKET="$1"
STACK_NAME="${2:-InventoryMonitorFimSample}"

# Parse optional parameters
MONITORED_PATH="/etc/paymentapp/"
FILE_PATTERNS="^/etc/paymentapp/config.*$"
SEVERITY="MEDIUM"
SCHEDULE="rate(30 minutes)"

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
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get current region
REGION="${AWS_DEFAULT_REGION:-$(aws configure get region)}"
if [ -z "$REGION" ] || [ "$REGION" = "None" ]; then
    REGION="us-east-1"
fi

echo "🚀 Deploying File Integrity Monitoring Solution"
echo "================================================"
echo "Deployment Bucket:  $DEPLOYMENT_BUCKET"
echo "Stack Name:         $STACK_NAME"
echo "Region:             $REGION"
echo "Monitored Path:     $MONITORED_PATH"
echo "File Patterns:      $FILE_PATTERNS"
echo "Severity:           $SEVERITY"
echo "Schedule:           $SCHEDULE"
echo ""



# Step 1: Package Lambda Layer
echo "📦 Step 1/4: Packaging Lambda Layer..."
rm -rf build
mkdir -p build/layer/python

cp layer/*.py build/layer/python/

if [ -f layer/requirements.txt ]; then
    python3 -m pip install -r layer/requirements.txt -t build/layer/python/ --quiet --disable-pip-version-check
fi

cd build/layer
zip -r ../../helpers_layer.zip python/ -q
cd ../..
echo "✅ Layer packaged: helpers_layer.zip"

# Step 2: Package Lambda Function
echo ""
echo "📦 Step 2/4: Packaging Lambda Function..."
zip -j fim-change-detector.zip lambda_function.py -q
echo "✅ Function packaged: fim-change-detector.zip"

# Step 3: Upload to S3
echo ""
echo "📤 Step 3/4: Uploading to S3..."
aws s3 cp helpers_layer.zip "s3://$DEPLOYMENT_BUCKET/layer/helpers_layer.zip"
aws s3 cp fim-change-detector.zip "s3://$DEPLOYMENT_BUCKET/lambda/fim-change-detector.zip"
echo "✅ Packages uploaded to s3://$DEPLOYMENT_BUCKET/"

# Step 4: Deploy CloudFormation
echo ""
echo "☁️  Step 4/4: Deploying CloudFormation stack..."
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
    --capabilities CAPABILITY_NAMED_IAM

echo ""
echo "✅ Deployment Complete!"
echo ""
echo "📦 What was deployed:"
echo "   ✓ S3 bucket for SSM Inventory data (versioned)"
echo "   ✓ SSM Resource Data Sync"
echo "   ✓ SSM Inventory Association (monitoring: $MONITORED_PATH)"
echo "   ✓ Lambda function with Layer"
echo "   ✓ S3 Event Notification (auto-configured)"
echo ""
echo "📋 Next Steps:"
echo "   1. Launch an EC2 instance with SSM agent"
echo "      - Attach IAM role with AmazonSSMManagedInstanceCore policy"
echo "      - Create test file in $MONITORED_PATH"
echo ""
echo "   2. Wait for inventory collection (schedule: $SCHEDULE)"
echo "      - Or manually trigger: Systems Manager → State Manager → Apply association now"
echo ""
echo "   3. Modify the test file to trigger a finding"
echo "      - Check Security Hub → Findings for detection"
echo ""
echo "🔍 View stack outputs:"
echo "   aws cloudformation describe-stacks --stack-name \"$STACK_NAME\" --query 'Stacks[0].Outputs'"
