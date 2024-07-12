#!/bin/bash
block_height=$(curl -s https://allora-rpc.edgenet.allora.network/block | jq -r .result.block.header.height)
response=$(curl --silent --location 'http://localhost:6000/api/v1/functions/execute' \
--header 'Content-Type: application/json' \
--data '{
    "function_id": "bafybeigpiwl3o73zvvl6dxdqu7zqcub5mhg65jiky2xqb4rdhfmikswzqm",
    "method": "allora-inference-function.wasm",
    "parameters": null,
    "topic": "1",
    "config": {
        "env_vars": [
            {
                "name": "BLS_REQUEST_PATH",
                "value": "/api"
            },
            {
                "name": "ALLORA_ARG_PARAMS",
                "value": "ETH"
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

echo "Response:"
echo "$response" | jq .
