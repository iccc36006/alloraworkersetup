#!/bin/bash
# Prompt for topic input
read -p "Enter topic (default: allora-topic-1-worker): " TOPIC
TOPIC=${TOPIC:-allora-topic-1-worker}

# Parse TOPIC_ID
TOPIC_ID=$(echo "$TOPIC" | awk -F'-' '{print $3}')

# Determine the token based on TOPIC_ID
case "$TOPIC_ID" in
    1) TOKEN="eth" ;;
    3) TOKEN="btc" ;;
    5) TOKEN="sol" ;;
    *) TOKEN="eth" ;; # Default action set to ETH for invalid TOPIC_ID
esac

# Get the current block height
block_height=$(curl -s https://allora-rpc.edgenet.allora.network/block | jq -r .result.block.header.height)

# Perform the curl request with the parsed topic and block height
response=$(curl --silent --location 'http://localhost:6000/api/v1/functions/execute' \
--header 'Content-Type: application/json' \
--data '{
    "function_id": "bafybeigpiwl3o73zvvl6dxdqu7zqcub5mhg65jiky2xqb4rdhfmikswzqm",
    "method": "allora-inference-function.wasm",
    "parameters": null,
    "topic": "'$TOPIC_ID'",
    "config": {
        "env_vars": [
            {
                "name": "BLS_REQUEST_PATH",
                "value": "/api"
            },
            {
                "name": "ALLORA_ARG_PARAMS",
                "value": "'$TOKEN'"
            },
            {
                "name": "ALLORA_BLOCK_HEIGHT_CURRENT",
                "value": "'$block_height'"
            }
        ],
        "number_of_nodes": -1,
        "timeout": 2
    }
}')

# Print the response
echo "Response:"
echo "$response" | jq .

