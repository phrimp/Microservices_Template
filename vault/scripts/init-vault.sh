#!/bin/sh

# Load environment variables from .env file if available
if [ -f /.env ]; then
  export $(grep -v '^#' /.env | xargs)
  echo "Loaded environment variables from /.env file"
fi

# Create vault config directory if it doesn't exist
mkdir -p /vault/config

# Generate vault.hcl configuration file
cat >/vault/config/vault.hcl <<EOF
storage "consul" {
  address = "${CONSUL_SERVER:-consul-server}:${CONSUL_HTTP_PORT:-8500}"
  path    = "${VAULT_CONSUL_PATH:-vault/}"
  token   = "${CONSUL_TOKEN:-}"
}

listener "tcp" {
  address     = "0.0.0.0:${VAULT_PORT:-8200}"
  tls_disable = ${VAULT_TLS_DISABLE:-1}
}

api_addr = "http://${VAULT_API_ADDR:-0.0.0.0}:${VAULT_PORT:-8200}"
ui = ${VAULT_UI_ENABLED:-true}
disable_mlock = ${VAULT_DISABLE_MLOCK:-true}
EOF

echo "Generated Vault configuration at /vault/config/vault.hcl"
cat /vault/config/vault.hcl

# Wait for Vault to be ready
echo "Waiting for Vault to start..."
until vault status >/dev/null 2>&1; do
  sleep 1
done

# Check if Vault is already initialized
if vault status | grep -q "Initialized.*true"; then
  echo "Vault is already initialized, skipping initialization"
else
  echo "Initializing Vault..."

  # Initialize Vault (in dev mode for simplicity - not for production!)
  vault operator init -key-shares=1 -key-threshold=1 -format=json >/tmp/vault_init.json

  # Extract keys
  VAULT_UNSEAL_KEY=$(cat /tmp/vault_init.json | jq -r ".unseal_keys_b64[0]")
  VAULT_ROOT_TOKEN=$(cat /tmp/vault_init.json | jq -r ".root_token")

  # Save to persistent location if needed
  echo "Unseal Key: $VAULT_UNSEAL_KEY"
  echo "Root Token: $VAULT_ROOT_TOKEN"

  # Unseal Vault
  vault operator unseal $VAULT_UNSEAL_KEY

  # Authenticate with root token
  vault login $VAULT_ROOT_TOKEN
fi

# Set token to provided one if we're in dev mode
if [ -n "$VAULT_DEV_ROOT_TOKEN_ID" ]; then
  TOKEN=$VAULT_DEV_ROOT_TOKEN_ID
  vault login $TOKEN
else
  # Get the token from initialization if available
  if [ -f /tmp/vault_init.json ]; then
    TOKEN=$(cat /tmp/vault_init.json | jq -r ".root_token")
    vault login $TOKEN
  fi
fi

# Enable KV secrets engine version 2
vault secrets enable -version=2 kv || echo "KV secrets engine already enabled"

# Store secrets from environment variables
echo "Storing secrets from environment variables..."

# Create a secrets.json file
cat >/tmp/secrets.json <<EOF
{
  "google": {
    "api_key": "${GOOGLE_API_KEY:-}",
    "client_secret": "${GOOGLE_CLIENT_SECRET:-}"
  },
  "database": {
    "password": "${DB_PASSWORD:-}"
  }
}
EOF

# Store secrets in Vault
vault kv put kv/google @/tmp/secrets.json

# Clean up
rm /tmp/secrets.json

# Enable AppRole auth method for service authentication
vault auth enable approle || echo "AppRole auth already enabled"

# Create policies
cat >/tmp/app-policy.hcl <<EOF
path "kv/data/google" {
  capabilities = ["read"]
}
EOF

vault policy write app-policy /tmp/app-policy.hcl

# Create AppRole with the policy attached
vault write auth/approle/role/app-role \
  token_policies="app-policy" \
  token_ttl=1h \
  token_max_ttl=24h

# Read the role ID for reference
ROLE_ID=$(vault read -field=role_id auth/approle/role/app-role/role-id)
echo "AppRole Role ID: $ROLE_ID"

# Generate a secret ID
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/app-role/secret-id)
echo "AppRole Secret ID: $SECRET_ID"

echo "Vault initialization and secret storage complete!"
