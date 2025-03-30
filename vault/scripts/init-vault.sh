#!/bin/bash

# Script to initialize Vault, unseal it, and store some example secrets
# Usage: ./init-vault.sh

# Enable debugging
set -x # Print commands as they're executed
set -e # Exit on error

# Log filesystem permissions
echo "Checking file system permissions:"
ls -la /vault/
ls -la /vault/file/ || echo "Directory doesn't exist yet"

echo "Waiting for Vault to be ready..."
until curl -s http://vault:8200/v1/sys/health | grep -q "initialized"; do
  sleep 5
done
echo "Vault is ready for initialization."

# Set Vault address
export VAULT_ADDR="http://vault:8200"

# Check if Vault is already initialized
INIT_STATUS=$(curl -s ${VAULT_ADDR}/v1/sys/init | jq -r .initialized)

if [ "$INIT_STATUS" = "false" ]; then
  echo "Initializing Vault..."

  # Initialize Vault and capture the output
  INIT_RESPONSE=$(curl -s \
    --request POST \
    --data '{"secret_shares": 1, "secret_threshold": 1}' \
    ${VAULT_ADDR}/v1/sys/init)

  # Extract root token and unseal key
  VAULT_TOKEN=$(echo $INIT_RESPONSE | jq -r .root_token)
  UNSEAL_KEY=$(echo $INIT_RESPONSE | jq -r .keys[0])

  echo "Vault initialized successfully"
  echo "Root Token: $VAULT_TOKEN"

  # Create directories if they don't exist
  mkdir -p /vault/file || echo "Directory /vault/file already exists"
  # Windows won't respect chmod the same way, so we'll just make sure directories exist
  mkdir -p /vault/keys || echo "Directory /vault/keys already exists"

  # Save keys to files (in production, you would distribute these securely)
  echo "Saving keys to multiple locations for redundancy"

  # First try to save to the host-mounted directory
  # Windows file access is different, so we'll try multiple approaches
  echo "Attempting to save keys to host-mounted directory..."

  # Try with jq
  echo $INIT_RESPONSE | jq . >/vault/keys/keys.json || echo "Warning: jq output to file may have failed"

  # Save in plain text format as well (more reliable for Windows)
  echo "Unseal Key: $UNSEAL_KEY" >/vault/keys/unseal-key.txt
  echo "Root Token: $VAULT_TOKEN" >/vault/keys/root-token.txt

  # Create a simple JSON format manually as a backup approach
  cat >/vault/keys/vault-keys-manual.json <<EOF
{
  "unseal_key": "$UNSEAL_KEY",
  "root_token": "$VAULT_TOKEN"
}
EOF

  echo "Attempted to save keys in multiple formats in /vault/keys/ directory (accessible from host)"
  ls -la /vault/keys

  # Also try the volume directory
  if echo $INIT_RESPONSE | jq . >/vault/file/keys.json; then
    chmod 644 /vault/file/keys.json || echo "Could not set permissions on file, continuing..."
    echo "Keys also saved to /vault/file/keys.json"
  else
    echo "WARNING: Could not write to /vault/file/keys.json"
  fi

  # Always save to /tmp as another fallback
  mkdir -p /tmp/vault
  if echo $INIT_RESPONSE | jq . >/tmp/vault/keys.json; then
    echo "Keys also saved to /tmp/vault/keys.json (container-only)"
  fi

  # Export keys to environment variables as final fallback
  export SAVED_UNSEAL_KEY=$UNSEAL_KEY
  export SAVED_ROOT_TOKEN=$VAULT_TOKEN
  echo "Keys also saved to environment variables as fallback"

  # Unseal Vault
  echo "Unsealing Vault..."
  curl -s \
    --request POST \
    --data "{\"key\": \"$UNSEAL_KEY\"}" \
    ${VAULT_ADDR}/v1/sys/unseal | jq .
else
  echo "Vault is already initialized."

  # Check if Vault is sealed
  SEAL_STATUS=$(curl -s ${VAULT_ADDR}/v1/sys/seal-status | jq -r .sealed)

  if [ "$SEAL_STATUS" = "true" ]; then
    echo "Vault is sealed. Retrieving unseal key..."

    # In production, you would obtain the key from a secure location
    # Try multiple locations for the keys
    if [ -f "/vault/file/keys.json" ]; then
      UNSEAL_KEY=$(cat /vault/file/keys.json | jq -r .keys[0])
      echo "Retrieved unseal key from /vault/file/keys.json"
    elif [ -f "/tmp/vault/keys.json" ]; then
      UNSEAL_KEY=$(cat /tmp/vault/keys.json | jq -r .keys[0])
      echo "Retrieved unseal key from /tmp/vault/keys.json"
    elif [ ! -z "$SAVED_UNSEAL_KEY" ]; then
      UNSEAL_KEY=$SAVED_UNSEAL_KEY
      echo "Using unseal key from environment variable"
    else
      echo "ERROR: Vault is sealed and no keys found in any expected location."
      echo "You may need to manually unseal Vault."
      exit 1
    fi

    echo "Unsealing Vault..."
    curl -s \
      --request POST \
      --data "{\"key\": \"$UNSEAL_KEY\"}" \
      ${VAULT_ADDR}/v1/sys/unseal | jq .
  fi

  # For this example, we'll use the root token from the saved file
  if [ -f "/vault/file/keys.json" ]; then
    VAULT_TOKEN=$(cat /vault/file/keys.json | jq -r .root_token)
    echo "Retrieved root token from /vault/file/keys.json"
  elif [ -f "/tmp/vault/keys.json" ]; then
    VAULT_TOKEN=$(cat /tmp/vault/keys.json | jq -r .root_token)
    echo "Retrieved root token from /tmp/vault/keys.json"
  elif [ ! -z "$SAVED_ROOT_TOKEN" ]; then
    VAULT_TOKEN=$SAVED_ROOT_TOKEN
    echo "Using root token from environment variable"
  else
    VAULT_TOKEN=${VAULT_DEV_ROOT_TOKEN_ID:-root}
    echo "WARNING: Using default or environment-provided root token."
  fi
fi

export VAULT_TOKEN="$VAULT_TOKEN"

echo "Waiting for Vault to become unsealed and active..."
until curl -s ${VAULT_ADDR}/v1/sys/health | grep -q '"sealed":false'; do
  sleep 2
done
echo "Vault is unsealed and active."

# Enable key-value secrets engine version 2
echo "Enabling KV secrets engine..."
vault secrets enable -version=2 kv || echo "KV engine might already be enabled"

# Create a simple key-value secret
echo "Creating example secrets..."
vault kv put kv/database/config username="db_user" password="$DB_PASSWORD"
vault kv put kv/google/api key="$GOOGLE_API_KEY" client_secret="$GOOGLE_CLIENT_SECRET"

# Create a policy for accessing database secrets
echo "Creating policies..."
vault policy write db-readonly - <<EOF
path "kv/data/database/*" {
  capabilities = ["read", "list"]
}
EOF

# Enable AppRole auth method for service authentication
echo "Enabling AppRole auth method..."
vault auth enable approle || echo "AppRole auth might already be enabled"

# Create an app role with the policy
echo "Creating app role..."
vault write auth/approle/role/api-service \
  secret_id_ttl=24h \
  token_ttl=1h \
  token_policies=db-readonly

echo "Vault has been successfully initialized with example configuration."
