#!/bin/bash

# Setup basic variables
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
YEAR_MONTH=$(date -u -d "1 hour ago" +"%Y/%m")
FILE_NAME=$(date -u -d "1 hour ago" +"%Y%m%d_%H%M%S.json")
ALL_LOGS="[]"
TOTAL_FETCHED=0

echo "Fetching logs from $START_TIME to $END_TIME..."

# Begin Pagination Loop
while true; do
    echo "Querying batch (Current total: $TOTAL_FETCHED)..."
    
    # Notice we sort by datetime_ASC (oldest to newest) to paginate safely
    QUERY='{
      viewer {
        accounts(filter: {accountTag: "'$ACCOUNT_ID'"}) {
          gatewayResolverQueriesAdaptiveGroups(
            limit: 1000,
            filter: {datetime_gt: "'$START_TIME'", datetime_leq: "'$END_TIME'"},
            orderBy: [datetime_ASC]
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

    # Extract the dimensions
    BATCH=$(echo "$RESPONSE" | jq -c '.data.viewer.accounts[0].gatewayResolverQueriesAdaptiveGroups | map(.dimensions)')
    BATCH_COUNT=$(echo "$BATCH" | jq 'length')

    if [[ "$BATCH" == "null" ]] || [[ $BATCH_COUNT -eq 0 ]]; then
        break # No more logs found, exit the loop
    fi

    # Merge this batch into our master list
    ALL_LOGS=$(echo "$ALL_LOGS $BATCH" | jq -s 'add')
    TOTAL_FETCHED=$((TOTAL_FETCHED + BATCH_COUNT))

    # If we got exactly 1000, there is probably more data. 
    # Update the START_TIME to the timestamp of the very last log in this batch.
    if [[ $BATCH_COUNT -eq 1000 ]]; then
        START_TIME=$(echo "$BATCH" | jq -r '.[-1].datetime')
    else
        break # We got less than 1000, meaning we hit the end of the data.
    fi
done

echo "Finished fetching. Total logs: $TOTAL_FETCHED"

if [[ $TOTAL_FETCHED -eq 0 ]]; then
    echo "No logs found to sync."
    exit 0
fi

# HOT STORAGE: Push ALL logs to Axiom
echo "Pushing $TOTAL_FETCHED logs to Axiom..."
curl -s -X POST "https://api.axiom.co/v1/datasets/cloudflare-dns/ingest" \
  -H "Authorization: Bearer $AXIOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$ALL_LOGS"

# COLD STORAGE: Save to GitHub
echo "Archiving to GitHub..."
mkdir -p "logs/$YEAR_MONTH"
echo "$ALL_LOGS" > "logs/$YEAR_MONTH/$FILE_NAME"

git config --global user.email "github-actions[bot]@users.noreply.github.com"
git config --global user.name "github-actions[bot]"

git add "logs/$YEAR_MONTH/$FILE_NAME"
git commit -m "Auto-archive $TOTAL_FETCHED logs for $FILE_NAME"
git push origin main

echo "Sync and Archive Complete!"
