#!/bin/bash

START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Syncing logs from $START_TIME..."

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

RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/graphql" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data "$(jq -n --arg query "$QUERY" '{query: $query}')")

LOGS=$(echo "$RESPONSE" | jq -c '.data.viewer.accounts[0].gatewayResolverQueriesAdaptiveGroups | map(.dimensions)')

if [[ "$LOGS" == "null" ]] || [[ $(echo "$LOGS" | jq 'length') -eq 0 ]]; then
    echo "No logs found."
    exit 0
fi

# Send the batch to Google Sheets
curl -L -X POST "$GOOGLE_SCRIPT_URL" \
     -H "Content-Type: application/json" \
     -d "$LOGS"

echo "Success: $(echo "$LOGS" | jq 'length') logs synced."
