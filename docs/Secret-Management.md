# Secret Management with Vault

HashiCorp Vault provides secure secret storage and management for the microservice architecture. This page explains how to manage secrets using Vault.

## Secret Storage Approaches

The architecture uses two different approaches for configuration vs secrets:

| `.env` File (Root Directory) | HashiCorp Vault |
|------------------------------|-----------------|
| Service configuration parameters | Sensitive credentials and secrets |
| Container startup environment variables | API keys, tokens, and passwords |
| Port mappings and network settings | Database connection strings |
| Feature flags and operational modes | Encryption keys |
| Log levels and debugging options | TLS certificates and private keys |
| Non-sensitive configuration values | OAuth client secrets |

## Adding Secrets to Vault

### Using JSON Files

The template includes a script that automatically loads secrets from JSON files in the `/vault/secrets` directory.

1. Create a JSON file with your secrets:

**database-secrets.json:**
```json
{
  "username": "app_user",
  "password": "strongP@ssw0rd123!",
  "host": "db.example.com",
  "port": 5432,
  "database": "production_db",
  "ssl": true,
  "max_connections": 20,
  "connection_timeout": 30,
  "encryption_key": "ahF8jUxVs9WrPzX6bQnT7EcRdL2mY5Kg"
}
```

2. Place the file in the `./vault/secrets` directory (which is mapped to `/vault/secrets` in the container).

3. Restart the vault-init container or run the loader script:

```bash
docker-compose restart vault-init
```

### Using the Vault CLI

You can also add secrets manually using the Vault CLI:

```bash
# Set VAULT_ADDR and VAULT_TOKEN environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ./vault/keys/root-token.txt | awk '{print $3}')

# Add a simple secret
vault kv put kv/services/api/mailserver \
  host=smtp.example.com \
  port=587 \
  username=mailer@example.com \
  password=mailpassword123

# Add a secret from a JSON file
vault kv put kv/services/database/analytics @analytics-db.json

# Read a secret
vault kv get kv/services/api/mailserver

# Update an existing secret (only changes specified fields)
vault kv patch kv/services/api/mailserver \
  password=newpassword456
```

## Organizing Secrets

Organize your secrets in a structured way:

```
vault/
└── secrets/
    ├── database/
    │   ├── prod-db.json
    │   └── staging-db.json
    ├── api/
    │   ├── google-api.json
    │   └── payment-gateway.json
    └── certificates/
        └── tls-keys.json
```

The `vault-secrets-loader.sh` script will:
1. Read all JSON files recursively from the secrets directory
2. Load them into Vault's KV store with paths matching the directory structure
3. Apply proper permissions based on the configured policies

## Accessing Secrets from Services

### Using the Vault HTTP API

For direct HTTP access:

```javascript
// Node.js example
const axios = require('axios');

async function getSecretFromVault() {
  try {
    const response = await axios.get('http://vault:8200/v1/kv/data/services/database', {
      headers: {
        'X-Vault-Token': process.env.VAULT_TOKEN
      }
    });
    
    return response.data.data.data;
  } catch (error) {
    console.error('Error retrieving secret:', error);
    throw error;
  }
}
```

### Using Official Vault Clients

Most languages have official Vault clients:

#### Java

```java
import io.github.jopenlibs.vault.Vault;
import io.github.jopenlibs.vault.VaultConfig;
import io.github.jopenlibs.vault.response.LogicalResponse;

// Create Vault client
final VaultConfig config = new VaultConfig()
    .address("http://vault:8200")
    .token(System.getenv("VAULT_TOKEN"))
    .build();

final Vault vault = new Vault(config);

// Read secret
final LogicalResponse response = vault.logical()
    .read("kv/data/services/database");

final String username = response.getData().get("data").get("username").asText();
final String password = response.getData().get("data").get("password").asText();
```

#### Python

```python
import hvac
import os

# Create client and authenticate
client = hvac.Client(url='http://vault:8200', token=os.environ['VAULT_TOKEN'])

# Read secret
secret_response = client.secrets.kv.v2.read_secret_version(
    path='services/database',
    mount_point='kv'
)

username = secret_response['data']['data']['username']
password = secret_response['data']['data']['password']
```

#### Node.js

```javascript
const vault = require('node-vault')({
  apiVersion: 'v1',
  endpoint: 'http://vault:8200',
  token: process.env.VAULT_TOKEN
});

async function getSecret() {
  try {
    const result = await vault.read('kv/data/services/database');
    const { username, password } = result.data.data;
    return { username, password };
  } catch (error) {
    console.error('Error fetching secret:', error);
    throw error;
  }
}
```

#### Go

```go
package main

import (
	"fmt"
	"os"

	vault "github.com/hashicorp/vault/api"
)

func getSecret() (map[string]interface{}, error) {
	config := vault.DefaultConfig()
	config.Address = "http://vault:8200"

	client, err := vault.NewClient(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create vault client: %w", err)
	}

	client.SetToken(os.Getenv("VAULT_TOKEN"))

	secret, err := client.Logical().Read("kv/data/services/database")
	if err != nil {
		return nil, fmt.Errorf("failed to read secret: %w", err)
	}

	data := secret.Data["data"].(map[string]interface{})
	return data, nil
}
```

## Service Authentication with AppRole

Instead of using a static token, services should use AppRole authentication:

1. Create an AppRole and policy for your service:

```bash
# Create a policy
vault policy write my-service-policy - <<EOF
path "kv/data/services/my-service/*" {
  capabilities = ["read", "list"]
}
EOF

# Create an AppRole
vault write auth/approle/role/my-service \
  secret_id_ttl=24h \
  token_ttl=1h \
  token_policies=my-service-policy
```

2. Generate credentials for your service:

```bash
# Get the RoleID
ROLE_ID=$(vault read -field=role_id auth/approle/role/my-service/role-id)

# Generate a SecretID
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/my-service/secret-id)

# Store these securely and provide them to your service
echo "ROLE_ID: $ROLE_ID"
echo "SECRET_ID: $SECRET_ID"
```

3. Authenticate your service with AppRole:

```javascript
// Node.js example
const vault = require('node-vault')();

async function authenticateWithVault() {
  try {
    const result = await vault.approleLogin({
      role_id: process.env.VAULT_ROLE_ID,
      secret_id: process.env.VAULT_SECRET_ID
    });
    
    const token = result.auth.client_token;
    vault.token = token;
    
    // Now you can use vault to read secrets
    const secret = await vault.read('kv/data/services/my-service/config');
    return secret.data.data;
  } catch (error) {
    console.error('Vault authentication error:', error);
    throw error;
  }
}
```

## Advanced Vault Features

### Dynamic Database Credentials

Generate temporary database credentials on-demand:

```bash
# Enable the database secrets engine
vault secrets enable database

# Configure a database connection
vault write database/config/my-database \
  plugin_name=mysql-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(db:3306)/" \
  allowed_roles="readonly" \
  username="root" \
  password="rootpassword"

# Create a role with limited permissions
vault write database/roles/readonly \
  db_name=my-database \
  creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}';GRANT SELECT ON *.* TO '{{name}}'@'%';" \
  default_ttl="1h" \
  max_ttl="24h"
```

Services can request temporary credentials:

```javascript
// Get dynamic credentials
const creds = await vault.read('database/creds/readonly');
const { username, password } = creds.data;

// Use these credentials to connect to the database
// They will automatically expire after the TTL
```

### Transit Encryption Engine

Encrypt data without handling encryption keys:

```bash
# Enable the transit engine
vault secrets enable transit

# Create a named encryption key
vault write -f transit/keys/my-key

# Encrypt data (must be base64-encoded)
curl -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
  --data '{"plaintext":"SGVsbG8gV29ybGQ="}' \
  http://vault:8200/v1/transit/encrypt/my-key
```

Services can use this for encryption without handling the keys:

```javascript
// Encrypt data
function encryptData(data) {
  const plaintext = Buffer.from(data).toString('base64');
  return vault.write('transit/encrypt/my-key', { plaintext });
}

// Decrypt data
function decryptData(encryptedData) {
  return vault.write('transit/decrypt/my-key', { ciphertext: encryptedData })
    .then(result => {
      return Buffer.from(result.data.plaintext, 'base64').toString();
    });
}
```

## Backing Up Vault Data

Back up Vault's encrypted data:

```bash
# Create a snapshot
vault operator raft snapshot save /vault/file/vault-backup.snap

# Copy the snapshot
docker cp vault:/vault/file/vault-backup.snap ./vault-backup.snap
```

## Best Practices

1. **Use AppRole authentication** rather than static tokens
2. **Implement lease renewal** for dynamic secrets
3. **Set appropriate TTLs** for tokens and dynamic secrets
4. **Use policies** to restrict access to specific paths
5. **Regularly rotate root tokens** and encryption keys
6. **Back up Vault data** and keep root tokens secure
7. **Log audit events** to track access to secrets
8. **Use namespaces** for different environments or teams
9. **Minimize secret duplication** across paths
10. **Never store secrets in version control**