# Detailed Setup Instructions

This page provides comprehensive setup instructions for deploying the microservice architecture template. Follow these steps to get your environment up and running.

## 1. Environment Configuration

First, set up your environment variables:

1. Review and modify the `.env` file to customize your environment:

```bash
# Make a copy of the example .env file (if needed)
cp .env.example .env

# Edit the file with your preferred editor
nano .env
```

### Important Variables

The following variables are important to review and adjust:

| Variable | Description | Default Value |
|----------|-------------|---------------|
| `CONSUL_HTTP_PORT` | Consul UI and API port | 8500 |
| `CONSUL_DNS_PORT` | Consul DNS port | 8600 |
| `TRAEFIK_HTTP_PORT` | HTTP port | 80 |
| `TRAEFIK_HTTPS_PORT` | HTTPS port | 443 |
| `TRAEFIK_DASHBOARD_PORT` | Traefik dashboard port | 8080 |
| `VAULT_PORT` | Vault UI and API port | 8200 |
| `CONSUL_LOG_LEVEL` | Consul logging level | INFO |
| `TRAEFIK_LOG_LEVEL` | Traefik logging level | INFO |
| `VAULT_LOG_LEVEL` | Vault logging level | INFO |

### Production Configuration Recommendations

For production environments, make the following changes:

- Generate a proper Consul encryption key (replace `CONSUL_ENCRYPT_KEY`)
- Set proper passwords and API keys
- Enable TLS (`TRAEFIK_TLS_ENABLED=true`)
- Disable insecure dashboard access (`TRAEFIK_DASHBOARD_INSECURE=false`)
- Set Vault to non-dev mode (`VAULT_DEV_MODE=false`)
- Enable Consul ACLs by uncommenting the ACL settings

## 2. Starting the Core Infrastructure

Start the core services (Consul, Traefik, and Vault):

```bash
docker-compose up -d
```

This command starts:
- **Consul server** for service discovery and configuration
- **Traefik** as the API gateway and load balancer
- **A helper container** to register Traefik middleware configurations in Consul
- **Vault** for secret management
- **Vault-init container** to initialize and configure Vault

### Verify Services are Running

Check that all services are running properly:

```bash
docker-compose ps
```

All services should show a status of `Up` or `Up (healthy)`.

### Check Service Logs

If you need to troubleshoot, check the logs:

```bash
# Check logs for all services
docker-compose logs

# Check logs for a specific service
docker-compose logs consul-server
docker-compose logs traefik
docker-compose logs vault
```

## 3. Access the Management Dashboards

Once the services are running, you can access their management dashboards:

- **Consul Dashboard**: http://localhost:8500
- **Traefik Dashboard**: http://localhost:8080
- **Vault Dashboard**: http://localhost:8200

### Initial Login to Vault

To log in to Vault, you'll need the root token:

```bash
# Get the root token
cat ./vault/keys/root-token.txt
```

Use this token to log in to the Vault UI or when using the Vault CLI.

## 4. Stopping the Infrastructure

To stop all services:

```bash
docker-compose down
```

To stop a specific service:

```bash
docker-compose stop <service-name>
```

## 5. Disabling Vault

If you want to run without Vault, you have several options:

### Option 1: Comment Out Vault Services

Edit the `docker-compose.yaml` file and comment out the Vault-related services:

```yaml
services:
  # Other services remain unchanged...
  
  # Comment out Vault services
  # vault:
  #   image: hashicorp/vault:1.16
  #   container_name: vault
  #   # ... rest of the configuration ...
  
  # vault-init:
  #   image: hashicorp/vault:1.19
  #   container_name: vault-init
  #   # ... rest of the configuration ...
```

### Option 2: Create a Minimal Docker Compose File

Create a simplified `docker-compose-no-vault.yaml` file:

```yaml
services:
  consul-server:
    # Consul configuration unchanged
    # ...

  traefik:
    # Traefik configuration unchanged
    # ...

  traefik-consul-register:
    # Registration script configuration unchanged
    # ...

networks:
  consul-net:
    driver: bridge
  traefik-net:
    driver: bridge

volumes:
  consul-data:
  traefik-net:
```

Use this file with:

```bash
docker-compose -f docker-compose-no-vault.yaml up -d
```

### Option 3: Environment Variable Toggle

1. Update `ENABLE_VAULT` variable to your `.env` file:
   ```
   ENABLE_VAULT=false
   ```

### Handling Secrets Without Vault

When running without Vault, you'll need an alternative way to manage secrets:

1. **Environment Variables**: Store secrets in `.env` files or export them directly
   ```bash
   echo "DB_PASSWORD=mypassword" >> .env
   ```

2. **Config Files**: Use configuration files with appropriate permissions
   ```bash
   echo '{"username": "admin", "password": "secret"}' > config/credentials.json
   chmod 600 config/credentials.json
   ```

## 6. Backing Up Core Infrastructure Data

### Backing Up Consul Data

Regularly back up Consul data:

```bash
docker exec consul-server consul snapshot save /consul/data/backup.snap
docker cp consul-server:/consul/data/backup.snap ./backup.snap
```

### Backing Up Vault Data

Back up Vault's encrypted data:

```bash
# Create a snapshot
vault operator raft snapshot save /vault/file/vault-backup.snap

# Copy the snapshot
docker cp vault:/vault/file/vault-backup.snap ./vault-backup.snap
```

## Next Steps

After setting up the core infrastructure, you can:

1. [Add services](Adding-Services) to your architecture
2. Configure [service registration](Service-Registration)
3. Set up [secret management](Secret-Management) for your services
4. Implement [health checks](Health-Checks) for all services