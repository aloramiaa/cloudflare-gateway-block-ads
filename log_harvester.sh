#!/bin/bash

# 1. Setup Timestamps and Folder Structure
# We define START_TIME to exactly 1 hour ago
START_TIME=$(date -u -d "1 hour ago" +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
YEAR_MONTH=$(date -u -d "1 hour ago" +"%Y/%m")
FILE_NAME=$(date -u -d "1 hour ago" +"%Y%m%d_%H%M%S.json")

ALL_LOGS="[]"
TOTAL_FETCHED=0

echo "Fetching logs from $START_TIME to $END_TIME..."

# 2. Begin Pagination Loop
# This loop keeps asking for data until it runs out of logs
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

    # Fetch from Cloudflare
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

    # If we got exactly 1000, there is more data waiting. 
    # Update START_TIME to the exact timestamp of the very last log.
    if [[ $BATCH_COUNT -eq 1000 ]]; then
        START_TIME=$(echo "$BATCH" | jq -r '.[-1].datetime')
    else
        break # We hit the end of the data
    fi
done

echo "Finished fetching. Total logs: $TOTAL_FETCHED"

if [[ $TOTAL_FETCHED -eq 0 ]]; then
    echo "No logs found to sync."
    exit 0
fi

# 3. COLD STORAGE: Save to GitHub FIRST
# We must create the file first so curl can read it directly from disk
echo "Archiving to GitHub..."
mkdir -p "logs/$YEAR_MONTH"
FILE_PATH="logs/$YEAR_MONTH/$FILE_NAME"
echo "$ALL_LOGS" > "$FILE_PATH"

# 4. HOT STORAGE: Push the FILE to Axiom
# The '@' symbol tells curl to upload the file contents directly, 
# bypassing the Linux character limit completely.
echo "Pushing $TOTAL_FETCHED logs to Axiom..."
curl -s -X POST "https://api.axiom.co/v1/datasets/cloudflare-dns/ingest" \
  -H "Authorization: Bearer $AXIOM_TOKEN" \
  -H "Content-Type: application/json" \
  -d @"$FILE_PATH"

# 5. Commit to GitHub Archive
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git config --global user.name "github-actions[bot]"

git add "$FILE_PATH"
git commit -m "Auto-archive $TOTAL_FETCHED logs for $FILE_NAME"
git push origin main

echo "Sync and Archive Complete!"
