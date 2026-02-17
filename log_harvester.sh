#!/bin/bash

# Configuration - These should be in your GitHub Secrets
# API_TOKEN: Your Cloudflare API Token
# ACCOUNT_ID: Your Cloudflare Account ID
# GOOGLE_SCRIPT_URL: The Web App URL from Step 1

# Calculate time range (Last 1 hour)
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Fetching logs from $START_TIME to $END_TIME..."

# 1. Pull logs from Cloudflare Gateway
# Note: We use the account-level Gateway logging endpoint
LOGS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/gateway/logs/dns?start=${START_TIME}&end=${END_TIME}" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json")

# Check if logs were returned
if [[ $(echo $LOGS | jq '.result | length') -eq 0 ]]; then
    echo "No new logs found for this period."
    exit 0
fi

# 2. Format logs and send to Google Sheets
# We extract only the fields you need for your dashboard
FORMATTED_LOGS=$(echo $LOGS | jq -c '.result | map({
    timestamp: .datetime,
    deviceName: .deviceName,
    queryName: .queryName,
    queryType: .queryType,
    action: .action,
    locationName: .locationName
})')

curl -L -X POST "$GOOGLE_SCRIPT_URL" \
     -H "Content-Type: application/json" \
     -d "$FORMATTED_LOGS"

echo "Logs successfully pushed to Google Sheets."
