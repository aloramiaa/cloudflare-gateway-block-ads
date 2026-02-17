#!/bin/bash

# 1. Setup Timestamps and Folder Structure
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
YEAR_MONTH=$(date -u -d "1 hour ago" +"%Y/%m")
FILE_NAME=$(date -u -d "1 hour ago" +"%Y%m%d_%H%M%S.json")

echo "Fetching logs from $START_TIME..."

# 2. Query Cloudflare
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
    echo "No new logs found."
    exit 0
fi

TOTAL=$(echo "$LOGS" | jq 'length')
echo "Found $TOTAL logs."

# 3. HOT STORAGE: Send to Axiom Dashboard
echo "Pushing to Axiom..."
curl -s -X POST "https://api.axiom.co/v1/datasets/cloudflare-dns/ingest" \
  -H "Authorization: Bearer $AXIOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$LOGS"

# 4. COLD STORAGE: Save to GitHub permanently
echo "Archiving to GitHub..."
mkdir -p "logs/$YEAR_MONTH"
echo "$LOGS" > "logs/$YEAR_MONTH/$FILE_NAME"

# Git setup for the GitHub Action Bot
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git config --global user.name "github-actions[bot]"

git add "logs/$YEAR_MONTH/$FILE_NAME"
git commit -m "Auto-archive $TOTAL logs for $START_TIME"
git push origin main

echo "Sync and Archive Complete!"
