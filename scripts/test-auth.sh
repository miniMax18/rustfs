#!/bin/bash

# Test script to verify RustFS authentication
# This script tests the S3 API authentication with the configured credentials

ACCESS_KEY="rustfsadmin"
SECRET_KEY="rustfsadmin"
ENDPOINT="http://localhost:9000"

echo "Testing RustFS Authentication..."
echo "==============================="
echo "Access Key: $ACCESS_KEY"
echo "Secret Key: $SECRET_KEY"
echo "Endpoint: $ENDPOINT"
echo ""

# Test 1: List buckets
echo "Test 1: Listing buckets"
echo "Command: aws s3 ls --endpoint-url=$ENDPOINT"
echo "------------------------"
AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY aws s3 ls --endpoint-url=$ENDPOINT

echo ""

# Test 2: Create a test bucket
echo "Test 2: Creating test bucket"
echo "Command: aws s3 mb s3://test-bucket --endpoint-url=$ENDPOINT"
echo "------------------------"
AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY aws s3 mb s3://test-bucket --endpoint-url=$ENDPOINT

echo ""

# Test 3: List buckets again
echo "Test 3: Listing buckets again"
echo "Command: aws s3 ls --endpoint-url=$ENDPOINT"
echo "------------------------"
AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY aws s3 ls --endpoint-url=$ENDPOINT

echo ""

# Test 4: Upload a test file
echo "Test 4: Uploading test file"
echo "hello world" > /tmp/test.txt
echo "Command: aws s3 cp /tmp/test.txt s3://test-bucket/test.txt --endpoint-url=$ENDPOINT"
echo "------------------------"
AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY aws s3 cp /tmp/test.txt s3://test-bucket/test.txt --endpoint-url=$ENDPOINT

echo ""

# Test 5: List objects in bucket
echo "Test 5: Listing objects in bucket"
echo "Command: aws s3 ls s3://test-bucket --endpoint-url=$ENDPOINT"
echo "------------------------"
AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY aws s3 ls s3://test-bucket --endpoint-url=$ENDPOINT

echo ""

# Test 6: Download the file
echo "Test 6: Downloading the file"
echo "Command: aws s3 cp s3://test-bucket/test.txt /tmp/test-download.txt --endpoint-url=$ENDPOINT"
echo "------------------------"
AWS_ACCESS_KEY_ID=$ACCESS_KEY AWS_SECRET_ACCESS_KEY=$SECRET_KEY aws s3 cp s3://test-bucket/test.txt /tmp/test-download.txt --endpoint-url=$ENDPOINT

echo "Downloaded content:"
cat /tmp/test-download.txt

echo ""
echo "Authentication test completed!"
echo "=============================="

# Clean up
rm -f /tmp/test.txt /tmp/test-download.txt
