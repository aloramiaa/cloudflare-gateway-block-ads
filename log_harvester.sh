#!/bin/bash

# 1. Calculate time range (Last 1 hour)
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Querying Gateway fields from $START_TIME..."

# 2. GraphQL Query using ONLY verified fields from your terminal output
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
          locationName
          queryName
          resolverDecision
        }
      }
    }
  }
}'

# 3. Execute the query
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/graphql" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data "$(jq -n --arg query "$QUERY" '{query: $query}')")

# 4. Check for errors
if echo "$RESPONSE" | jq -e '.errors' > /dev/null; then
    echo "Error from Cloudflare:"
    echo "$RESPONSE" | jq '.errors'
    exit 1
fi

# 5. Extract and show logs in terminal
LOGS=$(echo "$RESPONSE" | jq -c '.data.viewer.accounts[0].gatewayResolverQueriesAdaptiveGroups | map(.dimensions)')

if [[ "$LOGS" == "null" ]] || [[ $(echo "$LOGS" | jq 'length') -eq 0 ]]; then
    echo "No logs found for this period."
    exit 0
fi

echo "--- DATA PREVIEW ---"
echo "$LOGS" | jq '.'
echo "--- END DATA PREVIEW ---"

# 6. Send to Google Sheets
echo "Sending to Google Sheets..."
curl -L -X POST "$GOOGLE_SCRIPT_URL" \
     -H "Content-Type: application/json" \
     -d "$LOGS"

echo "Success!"
