#!/bin/bash

# Calculate time range (Last 1 hour)
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Querying Gateway Analytics for logs from $START_TIME..."

# The GraphQL Query using the correct field for Free/Pro accounts
QUERY='{
  viewer {
    accounts(filter: {accountTag: "'$ACCOUNT_ID'"}) {
      gatewayResolverQueriesAdaptiveGroups(
        limit: 1000,
        filter: {datetime_geq: "'$START_TIME'", datetime_leq: "'$END_TIME'"},
        orderBy: [datetime_DESC]
      ) {
        dimensions {
          datetime
          deviceName
          queryName
          queryType
          resolverDecision
          locationName
        }
      }
    }
  }
}'

# Execute the query
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/graphql" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data "$(jq -n --arg query "$QUERY" '{query: $query}')")

# Check for errors
if echo "$RESPONSE" | jq -e '.errors' > /dev/null; then
    echo "GraphQL Error:"
    echo "$RESPONSE" | jq '.errors'
    exit 1
fi

# Extract the dimensions into a flat array for the Google Sheet
LOGS=$(echo "$RESPONSE" | jq -c '.data.viewer.accounts[0].gatewayResolverQueriesAdaptiveGroups | map(.dimensions)')

if [[ "$LOGS" == "null" ]] || [[ $(echo "$LOGS" | jq 'length') -eq 0 ]]; then
    echo "No logs found for this period."
    exit 0
fi

echo "Found $(echo "$LOGS" | jq 'length') logs. Sending to Google Sheets..."

# Send to Google Sheets Web App
curl -L -X POST "$GOOGLE_SCRIPT_URL" \
     -H "Content-Type: application/json" \
     -d "$LOGS"

echo "Success!"
