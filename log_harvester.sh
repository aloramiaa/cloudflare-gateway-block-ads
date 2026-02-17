#!/bin/bash

# Ensure required variables are set
if [ -z "$API_TOKEN" ] || [ -z "$ACCOUNT_ID" ] || [ -z "$GOOGLE_SCRIPT_URL" ]; then
    echo "Error: Missing required environment variables (API_TOKEN, ACCOUNT_ID, or GOOGLE_SCRIPT_URL)"
    exit 1
fi

# Calculate time range (Last 1 hour)
# Note: Use -u for UTC as Cloudflare API expects UTC
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Fetching logs from $START_TIME to $END_TIME..."

# 1. Pull logs from Cloudflare Gateway
RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/gateway/logs/dns?start=${START_TIME}&end=${END_TIME}" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json")

# Debugging: Check if the response is valid JSON and contains "result"
if ! echo "$RESPONSE" | jq -e '.result' > /dev/null 2>&1; then
    echo "Full API Error Response:"
    echo "$RESPONSE" | jq '.' || echo "$RESPONSE"
    exit 1
fi

# 2. Check if logs were returned
LOG_COUNT=$(echo "$RESPONSE" | jq '.result | length')
if [[ $LOG_COUNT -eq 0 ]]; then
    echo "No new logs found for this period."
    exit 0
fi

echo "Found $LOG_COUNT logs. Formatting and sending to Google Sheets..."

# 3. Format and send
FORMATTED_LOGS=$(echo "$RESPONSE" | jq -c '.result | map({
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

echo "Done!"
