#!/bin/bash

# This query asks Cloudflare: "What fields can I actually use in this dataset?"
QUERY='{
  __type(name: "AccountGatewayResolverQueriesAdaptiveGroupsDimensions") {
    fields {
      name
    }
  }
}'

RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/graphql" \
     -H "Authorization: Bearer ${API_TOKEN}" \
     -H "Content-Type: application/json" \
     --data "$(jq -n --arg query "$QUERY" '{query: $query}')")

echo "--- START CLOUDFLARE SCHEMA RESPONSE ---"
echo "$RESPONSE" | jq '.'
echo "--- END CLOUDFLARE SCHEMA RESPONSE ---"
