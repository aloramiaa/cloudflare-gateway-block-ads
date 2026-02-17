#!/bin/bash

# Time range: Last 1 hour
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Syncing Cloudflare Logs from $START_TIME..."

# GraphQL Query using only the fields verified by your schema introspection
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

# Execute query to Cloudflare
RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/graphql" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data "$(jq -n --arg query "$QUERY" '{query: $query}')")

# Extract the data array
LOGS=$(echo "$RESPONSE" | jq -c '.data.viewer.accounts[0].gatewayResolverQueriesAdaptiveGroups | map(.dimensions)')

if [[ "$LOGS" == "null" ]] || [[ $(echo "$LOGS" | jq 'length') -eq 0 ]]; then
    echo "No new logs found in the last hour."
    exit 0
fi

echo "Found $(echo "$LOGS" | jq 'length') logs. Batch uploading..."

# Optimized curl for Google Apps Script (handles redirects and large payloads)
curl -L -s -o /dev/null -w "HTTP Status: %{http_code} | Total Time: %{time_total}s\n" \
     -X POST "$GOOGLE_SCRIPT_URL" \
     -H "Content-Type: application/json" \
     -H "Expect:" \
     -d "$LOGS"

echo "Sync Finished."
