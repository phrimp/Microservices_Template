#!/bin/sh
set -e

# Wait for Vault and Consul to be ready
echo "Waiting for Vault and Consul to start..."
until vault status >/dev/null 2>&1; do
  sleep 1
done
until consul members >/dev/null 2>&1; do
  sleep 1
done
echo "Vault and Consul are running"

# Configure Vault with Consul backend for dynamic configuration
echo "Configuring Vault to use Consul for dynamic configuration..."
vault secrets enable -path=dynamic-secrets kv-v2
vault secrets enable -path=secret kv-v2

# Initialize Consul KV store with secret type definitions
echo "Initializing Consul KV store with secret type definitions..."

# Register secret types in Consul
consul kv put secret-types/jwt '{"name": "JWT Key", "format": "pem", "fields": ["private_key", "public_key", "algorithm", "key_id"], "rotation_period": "90d"}'
consul kv put secret-types/oauth '{"name": "OAuth Credentials", "format": "json", "fields": ["client_id", "client_secret", "redirect_uri"], "rotation_period": "365d"}'
consul kv put secret-types/api-key '{"name": "API Key", "format": "string", "fields": ["key", "api_url", "description"], "rotation_period": "180d"}'
consul kv put secret-types/database '{"name": "Database Credentials", "format": "json", "fields": ["username", "password", "host", "port", "database"], "rotation_period": "30d"}'

# Create general policy templates in Consul
consul kv put policy-templates/read-only '{"description": "Read-only access to secrets", "capabilities": ["read"]}'
consul kv put policy-templates/admin '{"description": "Full access to secrets", "capabilities": ["create", "read", "update", "delete", "list"]}'

# Create service registry for automatic secret assignment
consul kv put service-registry/auth-service '{"description": "Authentication Service", "secret_types": ["jwt", "oauth"]}'
consul kv put service-registry/api-service '{"description": "API Service", "secret_types": ["jwt", "api-key"]}'

# Create base policies for secret management
echo "Creating base policies..."

# Secret management API policy
cat >/vault/policies/secret-management-policy.hcl <<EOF
# Allow management of the dynamic-secrets path
path "dynamic-secrets/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow management of the secret path
path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow management of policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow management of AppRole auth
path "auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF

vault policy write secret-management /vault/policies/secret-management-policy.hcl

# Enable AppRole auth method
echo "Enabling AppRole auth method..."
vault auth enable approle

# Configure roles
echo "Configuring roles..."

# Secret Management API role
vault write auth/approle/role/secret-management \
  token_ttl=1h \
  token_max_ttl=24h \
  token_policies=secret-management

# Auth service base role with minimal access - will be expanded dynamically
vault write auth/approle/role/auth-service \
  token_ttl=1h \
  token_max_ttl=24h \
  token_policies=default

# Generate and store credentials
echo "Generating credentials..."

SECRET_MGMT_ROLE_ID=$(vault read -format=json auth/approle/role/secret-management/role-id | jq -r .data.role_id)
SECRET_MGMT_SECRET_ID=$(vault write -format=json -f auth/approle/role/secret-management/secret-id | jq -r .data.secret_id)

AUTH_ROLE_ID=$(vault read -format=json auth/approle/role/auth-service/role-id | jq -r .data.role_id)
AUTH_SECRET_ID=$(vault write -format=json -f auth/approle/role/auth-service/secret-id | jq -r .data.secret_id)

# Save credentials to file for reference
mkdir -p /secrets
cat >/secrets/service_credentials.txt <<EOF
# Secret Management API Credentials
SECRET_API_ROLE_ID=$SECRET_MGMT_ROLE_ID
SECRET_API_SECRET_ID=$SECRET_MGMT_SECRET_ID

# Auth Service Credentials
AUTH_SERVICE_ROLE_ID=$AUTH_ROLE_ID
AUTH_SERVICE_SECRET_ID=$AUTH_SECRET_ID
EOF

# Now process any existing pre-generated secrets
echo "Processing pre-generated secrets..."

# Process JWT keys if they exist
if [ -f "/secrets/jwt_keys/jwt_private_key.pem" ] && [ -f "/secrets/jwt_keys/jwt_public_key.pem" ]; then
  echo "Found pre-generated JWT keys, storing in Vault..."

  # Read metadata if it exists, otherwise create default
  if [ -f "/secrets/jwt_keys/metadata.json" ]; then
    KID=$(jq -r '.key_id // "jwt-key-1"' /secrets/jwt_keys/metadata.json)
    ALG=$(jq -r '.algorithm // "RS256"' /secrets/jwt_keys/metadata.json)
  else
    KID="jwt-key-$(date +%Y%m%d)"
    ALG="RS256"
  fi

  # Store in Vault
  vault kv put dynamic-secrets/jwt/auth-service \
    private_key="$(cat /secrets/jwt_keys/jwt_private_key.pem)" \
    public_key="$(cat /secrets/jwt_keys/jwt_public_key.pem)" \
    algorithm="$ALG" \
    key_id="$KID" \
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    rotation_due="$(date -u -d "+90 days" +"%Y-%m-%dT%H:%M:%SZ")"

  # Store metadata in Consul
  consul kv put secret-metadata/jwt/auth-service "$(
    cat <<EOF
{
  "name": "JWT Signing Key for Auth Service",
  "type": "jwt",
  "path": "dynamic-secrets/jwt/auth-service",
  "key_id": "$KID",
  "algorithm": "$ALG",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "rotation_due": "$(date -u -d "+90 days" +"%Y-%m-%dT%H:%M:%SZ")",
  "owner": "auth-service",
  "consumers": ["auth-service", "api-service"]
}
EOF
  )"

  # Create policy for private key (auth service only)
  cat >/vault/policies/jwt-auth-service-policy.hcl <<EOF
path "dynamic-secrets/data/jwt/auth-service" {
  capabilities = ["read"]
}
EOF
  vault policy write jwt-auth-service /vault/policies/jwt-auth-service-policy.hcl

  # Update auth service role to include the new policy
  vault write auth/approle/role/auth-service token_policies="default,jwt-auth-service"

  echo "JWT keys stored successfully"
fi

# Process Google OAuth credentials if they exist
if [ -f "/secrets/google/credentials.json" ]; then
  echo "Found Google OAuth credentials, storing in Vault..."

  # Extract credentials from the file
  CLIENT_ID=$(jq -r '.client_id' /secrets/google/credentials.json)
  CLIENT_SECRET=$(jq -r '.client_secret' /secrets/google/credentials.json)
  REDIRECT_URI=$(jq -r '.redirect_uris[0] // "https://example.com/callback"' /secrets/google/credentials.json)

  # Store in Vault
  vault kv put dynamic-secrets/oauth/google \
    client_id="$CLIENT_ID" \
    client_secret="$CLIENT_SECRET" \
    redirect_uri="$REDIRECT_URI" \
    created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    rotation_due="$(date -u -d "+365 days" +"%Y-%m-%dT%H:%M:%SZ")"

  # Store metadata in Consul
  consul kv put secret-metadata/oauth/google "$(
    cat <<EOF
{
  "name": "Google OAuth Credentials",
  "type": "oauth",
  "path": "dynamic-secrets/oauth/google",
  "provider": "google",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "rotation_due": "$(date -u -d "+365 days" +"%Y-%m-%dT%H:%M:%SZ")",
  "owner": "auth-service",
  "consumers": ["auth-service"]
}
EOF
  )"

  # Create policy
  cat >/vault/policies/oauth-google-policy.hcl <<EOF
path "dynamic-secrets/data/oauth/google" {
  capabilities = ["read"]
}
EOF
  vault policy write oauth-google /vault/policies/oauth-google-policy.hcl

  # Update auth service role to include the new policy
  vault write auth/approle/role/auth-service token_policies="default,jwt-auth-service,oauth-google"

  echo "Google OAuth credentials stored successfully"
fi

# Process any API keys if they exist
if [ -d "/secrets/api-keys" ]; then
  echo "Processing API keys..."

  for API_FILE in /secrets/api-keys/*.json; do
    if [ -f "$API_FILE" ]; then
      API_NAME=$(basename "$API_FILE" .json)
      echo "Processing API key for: $API_NAME"

      # Extract data from the file
      API_KEY=$(jq -r '.api_key' "$API_FILE")
      API_URL=$(jq -r '.api_url // ""' "$API_FILE")
      DESCRIPTION=$(jq -r '.description // "API Key for '"$API_NAME"'"' "$API_FILE")

      # Store in Vault
      vault kv put dynamic-secrets/api-key/$API_NAME \
        key="$API_KEY" \
        api_url="$API_URL" \
        description="$DESCRIPTION" \
        created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        rotation_due="$(date -u -d "+180 days" +"%Y-%m-%dT%H:%M:%SZ")"

      # Store metadata in Consul
      consul kv put secret-metadata/api-key/$API_NAME "$(
        cat <<EOF
{
  "name": "$DESCRIPTION",
  "type": "api-key",
  "path": "dynamic-secrets/api-key/$API_NAME",
  "service": "$API_NAME",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "rotation_due": "$(date -u -d "+180 days" +"%Y-%m-%dT%H:%M:%SZ")",
  "owner": "auth-service",
  "consumers": ["auth-service"]
}
EOF
      )"

      # Create policy
      cat >/vault/policies/api-key-$API_NAME-policy.hcl <<EOF
path "dynamic-secrets/data/api-key/$API_NAME" {
  capabilities = ["read"]
}
EOF
      vault policy write api-key-$API_NAME /vault/policies/api-key-$API_NAME-policy.hcl

      # Update auth service role if needed
      if [ "$API_NAME" = "twilio" ] || [ "$API_NAME" = "sendgrid" ]; then
        CURRENT_POLICIES=$(vault read -format=json auth/approle/role/auth-service | jq -r '.data.token_policies | join(",")')
        vault write auth/approle/role/auth-service token_policies="$CURRENT_POLICIES,api-key-$API_NAME"
      fi

      echo "API key for $API_NAME stored successfully"
    fi
  done
fi

echo "Initialization complete!"
echo "Credentials saved to /secrets/service_credentials.txt"
