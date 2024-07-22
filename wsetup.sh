#!/bin/bash

execute_with_prompt() {
    echo "Executing: $1"
    if eval "$1"; then
        echo "Command executed successfully."
        echo
    else
        echo "Error executing command: $1"
        exit 1
    fi
}

read -p "I have read all the requirements and we can proceed with the installation: (Y/N): " response
echo

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Error: You need to accept server and package requirements! Exiting..."
    exit 1
fi

read -p "Enter topic (default: allora-topic-1-worker): " TOPIC
TOPIC=${TOPIC:-allora-topic-1-worker}

# Extract the topic ID using bash parameter expansion
TOPIC_ID=$(echo "$TOPIC" | awk -F'-' '{print $3}')

# Determine the token based on TOPIC_ID
case "$TOPIC_ID" in
    1) TOKEN="eth" ;;
    3) TOKEN="btc" ;;
    5) TOKEN="sol" ;;
    *) TOKEN="eth" ;; # Default action set to 1 (ETH) for invalid TOPIC_ID
esac

echo "Updating the package lists and upgrading all installed packages"
execute_with_prompt "sudo apt update -y && sudo apt upgrade -y"

echo "Installing requirements"
execute_with_prompt "sudo apt install ca-certificates zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev curl git wget make jq build-essential pkg-config lsb-release libssl-dev libreadline-dev libffi-dev gcc screen unzip lz4 -y"

echo "Installing python3 and pip"
execute_with_prompt "sudo apt install python3 python3-pip -y"

echo "Installing Docker"
execute_with_prompt 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg'
execute_with_prompt 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null'
execute_with_prompt 'sudo apt-get update'
execute_with_prompt 'sudo apt-get install docker-ce docker-ce-cli containerd.io -y'

echo "Docker version: "
execute_with_prompt 'docker version'

echo "Installing Docker Compose"
VER=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f 4)
execute_with_prompt 'sudo curl -L "https://github.com/docker/compose/releases/download/'"$VER"'/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose'
execute_with_prompt 'sudo chmod +x /usr/local/bin/docker-compose'

echo "Docker-compose version: "
execute_with_prompt 'docker-compose --version'

echo "Creating docker group"
if ! grep -q '^docker:' /etc/group; then
    execute_with_prompt 'sudo groupadd docker'
fi

echo "Adding current user to the docker group"
execute_with_prompt 'sudo usermod -aG docker $USER'

echo "Installing Go"
execute_with_prompt 'cd $HOME'
execute_with_prompt 'ver="1.22.4" && wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"'
execute_with_prompt 'sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"'
execute_with_prompt 'rm "go$ver.linux-amd64.tar.gz"'
execute_with_prompt 'echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile'
execute_with_prompt 'source $HOME/.bash_profile'

echo "Go version: "
execute_with_prompt 'go version'

echo "Cloning Allora-chain and compiling"
execute_with_prompt 'git clone https://github.com/allora-network/allora-chain.git'
execute_with_prompt 'cd allora-chain && make all'

echo "allorad version: "
execute_with_prompt 'allorad version'

# Ask user to choose wallet import or create new wallet
echo
echo "Would you like to import an existing wallet using 24 seeds or create a new wallet? Enter 1 or 2"
select choice in "1) Import" "2) Create New Wallet"; do
    case $REPLY in
        1)
            echo "Importing wallet!"
            read -p "Enter the wallet name: " WALLET_NAME
            execute_with_prompt "allorad keys add $WALLET_NAME --recover"
            break
            ;;
        2)
            echo "Creating a new wallet!"
            read -p "Enter the wallet name: " WALLET_NAME
            execute_with_prompt "allorad keys add $WALLET_NAME"
            break
            ;;
        *)
            echo "Invalid option. Please choose 1 or 2."
            ;;
    esac
done

echo "Do not forget to save your seeds!" 
echo
echo "Request tokens from the faucet using your wallet | faucet link: https://faucet.testnet-1.testnet.allora.network/"
echo
echo "Faucet step is required for worker registration"
read -n 1 -s -r -p "Please obtain tokens from the faucet. Press any key to continue once done..."

echo "Installing basic prediction node"
execute_with_prompt 'git clone https://github.com/allora-network/basic-coin-prediction-node'
execute_with_prompt 'cd basic-coin-prediction-node'
execute_with_prompt 'mkdir worker-data'
execute_with_prompt 'mkdir head-data'

echo "Setting required permissions"
execute_with_prompt 'sudo chmod -R 777 worker-data'
execute_with_prompt 'sudo chmod -R 777 head-data'

echo "Creating Head keys"
execute_with_prompt 'sudo docker run -it --entrypoint=bash -v $(pwd)/head-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"'

echo "Creating Worker keys"
execute_with_prompt 'sudo docker run -it --entrypoint=bash -v $(pwd)/worker-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"'

echo "Do not forget to save your head-id! Head ID:"
cat head-data/keys/identity
echo

if [ -f docker-compose.yml ]; then
    rm docker-compose.yml
fi

echo
HEAD_ID=$(cat head-data/keys/identity)
read -p "Enter WALLET_SEED_PHRASE: " WALLET_SEED_PHRASE

WALLET_SEED_PHRASE_ESCAPED="'$WALLET_SEED_PHRASE'"

echo "Generating docker-compose.yml file"
cat <<EOF > docker-compose.yml
version: '3'
services:
  inference:
    container_name: inference-basic-$TOKEN-pred
    build:
      context: .
    command: python -u /app/app.py
    ports:
      - "8000:8000"
    networks:
      $TOKEN-model-local:
        aliases:
          - inference
        ipv4_address: 172.22.0.4
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/inference/${TOKEN^^}"]
      interval: 10s
      timeout: 10s
      retries: 12
    volumes:
      - ./inference-data:/app/data

  updater:
    container_name: updater-basic-$TOKEN-pred
    build: .
    environment:
      - INFERENCE_API_ADDRESS=http://inference:8000
    command: >
      sh -c "
      while true; do
        python -u /app/update_app.py;
        sleep 24h;
      done
      "
    depends_on:
      inference:
        condition: service_healthy
    networks:
      $TOKEN-model-local:
        aliases:
          - updater
        ipv4_address: 172.22.0.5

  worker:
    container_name: worker-basic-$TOKEN-pred
    environment:
      - INFERENCE_API_ADDRESS=http://inference:8000
      - HOME=/data
    build:
      context: .
      dockerfile: Dockerfile_b7s
    entrypoint:
      - "/bin/bash"
      - "-c"
      - |
        if [ ! -f /data/keys/priv.bin ]; then
          echo "Generating new private keys..."
          mkdir -p /data/keys
          cd /data/keys
          allora-keys
        fi
        allora-node --role=worker --peer-db=/data/peerdb --function-db=/data/function-db \
          --runtime-path=/app/runtime --runtime-cli=bls-runtime --workspace=/data/workspace \
          --private-key=/data/keys/priv.bin --log-level=debug --port=9011 \
          --boot-nodes=/ip4/172.22.0.100/tcp/9010/p2p/$HEAD_ID \
          --topic=$TOPIC \
          --allora-chain-key-name=$WALLET_NAME \
          --allora-chain-restore-mnemonic=$WALLET_SEED_PHRASE_ESCAPED \
          --allora-node-rpc-address=https://allora-rpc.testnet-1.testnet.allora.network/ \
          --allora-chain-topic-id=$TOPIC_ID
    volumes:
      - ./worker-data:/data
    working_dir: /data
    depends_on:
      - inference
      - head
    networks:
      $TOKEN-model-local:
        aliases:
          - worker
        ipv4_address: 172.22.0.10

  head:
    container_name: head-basic-$TOKEN-pred
    image: alloranetwork/allora-inference-base-head:latest
    environment:
      - HOME=/data
    entrypoint:
      - "/bin/bash"
      - "-c"
      - |
        if [ ! -f /data/keys/priv.bin ]; then
          echo "Generating new private keys..."
          mkdir -p /data/keys
          cd /data/keys
          allora-keys
        fi
        allora-node --role=head --peer-db=/data/peerdb --function-db=/data/function-db  \
          --runtime-path=/app/runtime --runtime-cli=bls-runtime --workspace=/data/workspace \
          --private-key=/data/keys/priv.bin --log-level=debug --port=9010 --rest-api=:6000
    ports:
      - "6000:6000"
    volumes:
      - ./head-data:/data
    working_dir: /data
    networks:
      $TOKEN-model-local:
        aliases:
          - head
        ipv4_address: 172.22.0.100

networks:
  $TOKEN-model-local:
    driver: bridge
    ipam:
      config:
        - subnet: 172.22.0.0/24

volumes:
  inference-data:
  worker-data:
  head-data:
EOF

echo "docker-compose.yml file generated successfully!"

echo "Building Docker services"
docker-compose build
docker-compose up -d

echo "Checking the status of Docker containers:"
docker ps

echo "End of the script"
