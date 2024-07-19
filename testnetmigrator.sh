#!/bin/bash

# Request tokens from testnet faucet
echo "Request tokens from the faucet using your wallet | faucet link: https://faucet.testnet-1.testnet.allora.network/"
echo
echo "Faucet step is required for worker registration"
read -n 1 -s -r -p "Please obtain tokens from the faucet. Press any key to continue once done..."

# Extract the input YAML file path from the docker-compose ls output
INPUT_YAML=$(docker-compose ls | grep basic-coin-prediction-node | awk '{print $3}')

# If the input file does not exist, prompt for its path
if [ ! -f "$INPUT_YAML" ]; then
  echo "Error: The input YAML file $INPUT_YAML does not exist. Run <docker-compose ls> command enter the path under CONFIG FILES"
  read -p "Please provide the path to the input YAML file: " INPUT_YAML

  # Check if the provided file exists
  if [ ! -f "$INPUT_YAML" ]; then
    echo "Error: The provided file path $INPUT_YAML does not exist."
    exit 1
  fi
fi

# Define the output YAML file path
OUTPUT_YAML=$(echo "$INPUT_YAML" | sed 's/[^/]*$/docker-compose-testnet.yml/')

# Copy the content of the input YAML to the output YAML
cp "$INPUT_YAML" "$OUTPUT_YAML"

# Perform the necessary replacements
sed -i -e 's|--allora-node-rpc-address=https://allora-rpc.edgenet.allora.network/|--allora-node-rpc-address=https://allora-rpc.testnet-1.testnet.allora.network/|' "$OUTPUT_YAML"

# Make your docker services down
docker-compose down

# Remove the existing containers and corresponding images
echo "Stopping and removing existing Docker containers and images..."
docker stop $(docker ps -aq) 2>/dev/null
docker rm $(docker ps -aq) 2>/dev/null
docker rmi -f $(docker images -aq) 2>/dev/null

echo "Migration complete. The output file is $OUTPUT_YAML. Making your docker services up now!"
docker-compose --file "$OUTPUT_YAML" up -d


