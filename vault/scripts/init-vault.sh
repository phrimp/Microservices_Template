#!/bin/bash

# Script to initialize Vault and store some example secrets
# Usage: ./init-vault.sh

echo "Waiting for Vault to be ready..."
until curl -s http://vault:8200/v1/sys/health | grep -q "initialized"; do
  sleep 5
done
echo "Vault is ready."

# Set Vault address and token
export VAULT_ADDR="http://vault:8200"
export VAULT_TOKEN="root"

# Enable key-value secrets engine version 2
echo "Enabling KV secrets engine..."
vault secrets enable -version=2 kv

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
vault auth enable approle

# Create an app role with the policy
echo "Creating app role..."
vault write auth/approle/role/api-service \
  secret_id_ttl=24h \
  token_ttl=1h \
  token_policies=db-readonly

echo "Vault has been successfully initialized with example configuration."
