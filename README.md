# Quick Start

## Prerequisites

- Docker and Docker Compose installed
- Git installed
- Basic understanding of containerization and microservices
- Free ports as specified in the `.env` file (by default: 80, 443, 8080, 8500, 8600, 8200)

## Documentation

This microservices template provides a robust foundation for building scalable applications. The documentation is split between this README and the [project Wiki](../../wiki).

### Quick Links

| Topic | Description |
|-------|-------------|
| [Architecture](../../wiki/Architecture) | Detailed overview of the microservice architecture |
| [Core Component](../../wiki/Core-Components) | Detailed overview of the microservice component |
| [Advanced Features](../../wiki/Advanced-Feature) | Advanced Features for each Technology integrated |
| [Register Services](../../wiki/Register-Services) | Registering Services with Consul |

## Quick Setup Steps

1. Clone the repository
2. Configure environment variables
3. Start the core infrastructure
4. Register your first service
5. Access the dashboards

## Detailed Setup Instructions

### 1. Environment Configuration

1. Review and modify the `.env` file to customize your environment:

```bash
# Make a copy of the example .env file
cp .env.example .env

# Edit the file with your preferred editor
nano .env
```

Important variables to consider:
- `CONSUL_HTTP_PORT`: Consul UI and API port (default: 8500)
- `TRAEFIK_HTTP_PORT`: HTTP port (default: 80)
- `TRAEFIK_HTTPS_PORT`: HTTPS port (default: 443)
- `TRAEFIK_DASHBOARD_PORT`: Traefik dashboard port (default: 8080)
- `VAULT_PORT`: Vault UI and API port (default: 8200)

For production environments:
- Generate a proper Consul encryption key
- Set proper passwords and API keys
- Enable TLS
- Disable insecure dashboard access
- Set Vault to non-dev mode

### 2. Starting the Core Infrastructure

Start the core services (Consul, Traefik, and Vault):

```bash
docker-compose up -d
```

This command starts:
- Consul server for service discovery and configuration
- Traefik as the API gateway and load balancer
- A helper container to register Traefik middleware configurations in Consul
- Vault for secret management
- Vault-init container to initialize and configure Vault

Verify the services are running:

```bash
docker-compose ps
```

### 3. Access the Management Dashboards

- **Consul Dashboard**: http://localhost:8500
- **Traefik Dashboard**: http://localhost:8080
- **Vault Dashboard**: http://localhost:8200

### 4. Adding a Service to the Root Docker Compose with a Dockerfile

You can add your service directly to the root `docker-compose.yaml` file using a custom Dockerfile. This approach gives you full control over your service environment and is useful for:

- Development environments where you need to build from source
- Custom services that aren't available as pre-built images
- Services that require specific dependencies or configurations
- Projects where you want to keep everything in version control

Here's how to add a service with a Dockerfile to the root Docker Compose file:

1. Ensure you have a Dockerfile for your service at `./services/app-service/Dockerfile`:

   If you don't already have a Dockerfile, you can create one:

   ```bash
   mkdir -p ./services/app-service
   ```

   A simple Dockerfile might look like:

   ```Dockerfile
   # Choose a base image appropriate for your application
   FROM node:18-alpine
   
   # Set working directory
   WORKDIR /app
   
   # Copy dependency definitions
   COPY package*.json ./
   
   # Install dependencies
   RUN npm install
   
   # Copy application code
   COPY . .
   
   # Expose the port your application uses
   EXPOSE 8080
   
   # Define healthcheck
   HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
     CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
   
   # Command to run the application
   CMD ["npm", "start"]
   ```

2. Edit the `docker-compose.yaml` file and add your service configuration with a build directive:

```yaml
services:
  # Existing services (consul-server, traefik, etc.)
  
  # Add your new service with a Dockerfile
  app-service:
    build:
      context: ./services/app-service  # Path to your service directory containing the Dockerfile
      dockerfile: Dockerfile           # Name of the Dockerfile (if it's just "Dockerfile" this line is optional)
    container_name: app-service
    restart: unless-stopped
    environment:
      - SERVICE_NAME=app-service
      - NODE_ENV=development
      - DATABASE_URL=postgres://user:password@db:5432/mydatabase
      # Add other environment variables as needed
    ports:
      - "8081:8080"  # Map container port to host port if direct access is needed
    volumes:
      - ./services/app-service:/app  # Mount source code for development (optional)
      - /app/node_modules            # Prevent overwriting node_modules with local version
      - app-service-data:/app/data   # Persistent data volume
    networks:
      - traefik-net
      - consul-net
    depends_on:
      - consul-server
      - vault
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app-service.rule=PathPrefix(`/app`)"
      - "traefik.http.services.app-service.loadbalancer.server.port=8080"
      - "traefik.http.middlewares.app-strip-prefix.stripprefix.prefixes=/app"
      - "traefik.http.routers.app-service.middlewares=app-strip-prefix,rate-limit@consul,secure-headers@consul"
      - "traefik.docker.network=microservices_template_traefik-net"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

# Add any new volumes your service needs
volumes:
  # Existing volumes (consul-data, vault-file, etc.)
  app-service-data:
```

3. Build and start your service:

```bash
# Build and start your service
docker-compose up -d --build app-service

# If you want to see the build logs
docker-compose up --build app-service

# If starting all services from scratch
docker-compose up -d --build
```

4. Verify that your service is registered with Consul by checking the Consul dashboard or using the CLI:

```bash
# Using curl
curl http://localhost:8500/v1/catalog/service/app-service

# Or check the Consul UI at http://localhost:8500
```

5. Test that Traefik is properly routing to your service:

```bash
curl http://localhost/app/
```

6. For development, you can easily rebuild after code changes:

```bash
# Rebuild and restart the service with latest code changes
docker-compose up -d --build app-service
```

### 5. Service Lifecycle Management

When your service is part of the root Docker Compose file, its lifecycle is managed together with the core infrastructure:

- **Starting all services**: `docker-compose up -d`
- **Stopping all services**: `docker-compose down`
- **View logs for a specific service**: `docker-compose logs api-service`
- **Restart a specific service**: `docker-compose restart api-service`
- **Scale a service**: `docker-compose up -d --scale api-service=3` (requires proper configuration for scaling)

### 6. Health Checks and Status Monitoring

With the service defined in the root Docker Compose file, you can monitor its health status:

- Through Docker: `docker-compose ps` will show the health status
- Through Consul UI: Check the health status in the Services tab
- Through Consul API: `curl http://localhost:8500/v1/health/service/api-service?passing`

### 7. Service Configuration Management

For service-specific configurations:

1. Create a config directory for your service:

```bash
mkdir -p ./api-service/config
```

2. Add configuration files that will be mounted to the container:

```bash
# Example config file
cat > ./api-service/config/app-config.json << EOF
{
  "logLevel": "info",
  "timeout": 30,
  "features": {
    "caching": true,
    "metrics": true
  }
}
EOF
```

3. Update your service definition to mount this configuration:

```yaml
api-service:
  # ... other settings
  volumes:
    - ./api-service/config:/app/config
```

### 4. Adding a Microservice Using a Separate Docker Compose File

This was covered in the original documentation and remains a valid approach for more complex scenarios or when you want to keep services isolated.

Create a service directory:

```bash
mkdir -p services/my-service
cd services/my-service
```

Create a Docker Compose file (`docker-compose.yml`):

```yaml
services:
  my-service:
    image: your-image:tag
    container_name: my-service
    restart: unless-stopped
    networks:
      - traefik-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)"
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"
      - "traefik.http.routers.my-service.middlewares=rate-limit@consul,secure-headers@consul"
      - "traefik.docker.network=traefik-net"

networks:
  traefik-net:
    external: true
```

Start your service:

```bash
docker-compose up -d
```

## Secrets

- [Secret Loading](../../wiki/Advanced-Feature#secret-loading)


## Using Traefik Docker Labels

The template uses Traefik as an API gateway. Use Docker labels to configure routing:

### Basic Routing

```yaml
- "traefik.enable=true"  # Enable Traefik for this container
- "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)"  # Route based on path
- "traefik.http.services.my-service.loadbalancer.server.port=8080"  # Container port
```

### Apply Middlewares

```yaml
# Apply pre-configured middlewares from Consul
- "traefik.http.routers.my-service.middlewares=rate-limit@consul,secure-headers@consul"
```

### Enable HTTPS

```yaml
- "traefik.http.routers.my-service.tls=true"
- "traefik.http.routers.my-service.tls.certresolver=letsencrypt"
```

## Accessing Vault Secrets from Services

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

## Security Considerations

### 1. Environment Variables

- Never commit the `.env` file with sensitive information
- For production, use a secret management solution like HashiCorp Vault

### 2. Network Security

- Ensure proper network segmentation
- Limit exposed ports to only what's necessary
- Use TLS for all service communication

### 3. Access Control

- Enable Consul ACLs in production
- Secure the Traefik dashboard with authentication
- Use IP whitelisting for admin interfaces
- Implement Vault policies for fine-grained access control

## Monitoring and Maintenance

### Health Checks

The Docker Compose file includes health checks for core services. Use similar checks for your microservices:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 10s
  timeout: 5s
  retries: 3
```

### Backing Up Consul Data

Regularly back up Consul data:

```bash
docker exec consul-server consul snapshot save /consul/data/backup.snap
docker cp consul-server:/consul/data/backup.snap ./backup.snap
```

### Manually Loading Secrets into Vault

Besides the automatic loading done by the `vault-secrets-loader.sh` script, you can manually add secrets to Vault:

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

### Backing Up Vault Data

Back up Vault's encrypted data:

```bash
# Create a snapshot
vault operator raft snapshot save /vault/file/vault-backup.snap

# Copy the snapshot
docker cp vault:/vault/file/vault-backup.snap ./vault-backup.snap
```

## Creating a Service with a Dockerfile

Instead of using an existing image, you can build your own service image directly within the root docker-compose.yaml file. This approach is useful when you need custom functionality or when you're developing a new service.

### 1. Create Your Service Directory

First, create a directory for your service files:

```bash
mkdir -p services/my-custom-service
cd services/my-custom-service
```

### 2. Create a Dockerfile

Create a Dockerfile that defines your service:

```Dockerfile
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
COPY package*.json ./
RUN npm install

# Bundle app source
COPY . .

# Expose the port the app runs on
EXPOSE 3000

# Create a health check endpoint
RUN echo 'app.get("/health", (req, res) => res.status(200).send("OK"));' >> src/server.js

# Command to run the application
CMD ["node", "src/server.js"]
```

### 3. Create Your Application Files

Add your application code to the service directory. For a simple Node.js service:

```bash
# Create a basic package.json
cat > package.json << EOF
{
  "name": "my-custom-service",
  "version": "1.0.0",
  "description": "A custom microservice",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "consul": "^1.2.0"
  }
}
EOF

# Create source directory
mkdir -p src

# Create a simple Express server
cat > src/server.js << EOF
const express = require('express');
const Consul = require('consul');

const app = express();
const port = process.env.PORT || 3000;

// Initialize Consul client
const consul = new Consul({
  host: process.env.CONSUL_HOST || 'consul-server',
  port: process.env.CONSUL_PORT || 8500
});

// Register service with Consul
function registerService() {
  const serviceId = \`my-custom-service-\${process.env.HOSTNAME}\`;
  const serviceDefinition = {
    name: 'my-custom-service',
    id: serviceId,
    address: process.env.SERVICE_HOST || process.env.HOSTNAME,
    port: parseInt(port),
    tags: ['node', 'custom'],
    check: {
      http: \`http://\${process.env.HOSTNAME}:\${port}/health\`,
      interval: '10s',
      timeout: '5s'
    }
  };

  consul.agent.service.register(serviceDefinition, (err) => {
    if (err) {
      console.error('Error registering service:', err);
      return;
    }
    console.log('Service registered successfully with ID:', serviceId);
  });

  // Deregister on shutdown
  process.on('SIGINT', () => {
    consul.agent.service.deregister(serviceId, () => {
      console.log('Service deregistered');
      process.exit();
    });
  });
}

// Define routes
app.get('/', (req, res) => {
  res.send('Hello from my custom service!');
});

app.get('/health', (req, res) => {
  res.status(200).send('OK');
});

// Start the server
app.listen(port, () => {
  console.log(\`Service listening at http://localhost:\${port}\`);
  registerService();
});
EOF
```

### 4. Add the Service to docker-compose.yaml

Now, update your root docker-compose.yaml file to include the custom service:

```yaml
services:
  # Existing services (consul-server, traefik, etc.)
  
  # Add your custom service
  my-custom-service:
    build:
      context: ./services/my-custom-service
      dockerfile: Dockerfile
    container_name: my-custom-service
    restart: unless-stopped
    environment:
      - PORT=3000
      - CONSUL_HOST=consul-server
      - SERVICE_NAME=my-custom-service
    networks:
      - consul-net
      - traefik-net
    depends_on:
      - consul-server
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-custom-service.rule=PathPrefix(`/custom`)"
      - "traefik.http.services.my-custom-service.loadbalancer.server.port=3000"
      - "traefik.http.middlewares.custom-strip-prefix.stripprefix.prefixes=/custom"
      - "traefik.http.routers.my-custom-service.middlewares=custom-strip-prefix,rate-limit@consul,secure-headers@consul"
      - "traefik.docker.network=microservices_template_traefik-net"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--spider", "http://localhost:3000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### 5. Build and Start the Service

Build and start your custom service:

```bash
# Build and start only your custom service
docker-compose up -d --build my-custom-service

# Or build and start all services
docker-compose up -d --build
```

### 6. Verify Service Registration

Verify that your service is properly registered:

```bash
# Check Consul for service registration
curl http://localhost:8500/v1/catalog/service/my-custom-service

# Test the service through Traefik
curl http://localhost/custom/
```

### 7. Service Logs and Troubleshooting

Monitor your service logs for troubleshooting:

```bash
# View logs
docker-compose logs -f my-custom-service

# Check container status
docker-compose ps my-custom-service
```

### 8. Additional Dockerfile Examples

#### Python Service

```Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
```

#### Java Spring Boot Service

```Dockerfile
FROM maven:3.8.6-openjdk-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

FROM openjdk:17-slim
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

#### Go Service

```Dockerfile
FROM golang:1.21-alpine AS build

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o service ./cmd/server

FROM alpine:3.18
WORKDIR /app
COPY --from=build /app/service .
EXPOSE 8080
CMD ["./service"]
```

## Vault vs Environment Variables

### Role Separation

In this architecture, there's a clear separation of concerns between Vault and the `.env` file:

| `.env` File (Root Directory) | HashiCorp Vault |
|------------------------------|-----------------|
| Service configuration parameters | Sensitive credentials and secrets |
| Container startup environment variables | API keys, tokens, and passwords |
| Port mappings and network settings | Database connection strings |
| Feature flags and operational modes | Encryption keys |
| Log levels and debugging options | TLS certificates and private keys |
| Non-sensitive configuration values | OAuth client secrets |

### `.env` File Usage

The `.env` file in the root directory is used for:
- Defining ports for services (e.g., `TRAEFIK_HTTP_PORT=80`)
- Setting log levels (e.g., `CONSUL_LOG_LEVEL=INFO`)
- Configuring feature flags (e.g., `TRAEFIK_DASHBOARD_ENABLED=true`)
- Defining container startup parameters
- Setting network configuration
- Controlling which components are enabled

These values are not considered sensitive and are primarily used to configure how services start up and communicate with each other.

### Vault Usage

HashiCorp Vault is exclusively used for:
- Storing sensitive credentials that services need at runtime
- Managing API keys for external services
- Storing encryption keys used by applications
- Handling credentials that would pose a security risk if leaked
- Providing dynamic, short-lived credentials
- Managing certificates and private keys

### Comparing Secret Storage Approaches

| Feature | `.env` File (For Configuration) | HashiCorp Vault (For Secrets) |
|---------|--------------------------------|-------------------------------|
| **Security** | Minimal - stored as plaintext | High - encrypted at rest, in transit, and in memory |
| **Access Control** | None - accessible to anyone with file access | Fine-grained with policies |
| **Auditability** | No tracking of changes or access | Comprehensive audit logging |
| **Rotation** | Requires manual file edits and restarts | Can be rotated without restarts |
| **Revocation** | Requires file edits and restarts | Immediate revocation possible |
| **Integration** | Simple environment variable loading | More complex API-based access |
| **Dynamic Secrets** | Not supported | Fully supported |
| **Disaster Recovery** | Manual backup of files | Automated backup and recovery |

### Implementation Pattern in This Architecture

This architecture implements the following pattern:
1. **`.env` file** contains all service configuration parameters and non-sensitive settings needed at container startup time
2. **Vault** stores all sensitive information that services need to access at runtime
3. **Services** read their startup configuration from environment variables, then authenticate to Vault to obtain sensitive credentials

This separation ensures that configuration management and secret management are handled through appropriate channels with the right level of security for each.

## Disabling Vault

In some cases, you might want to run the architecture without Vault, either for simpler development environments or when using alternative secret management solutions.

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

2. Modify your deployment scripts to check this variable and use the appropriate configuration.

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

Remember that these alternatives generally offer less security than Vault, so assess your security requirements accordingly.

## Production Deployment Checklist

Before deploying to production:

- [ ] Generate new encryption keys and passwords
- [ ] Enable TLS for all services
- [ ] Secure all admin interfaces
- [ ] Set up proper backup procedures
- [ ] Configure monitoring and alerting
- [ ] Implement proper logging
- [ ] Test failover scenarios
- [ ] Document the deployment process
- [ ] Enable Consul ACLs
- [ ] Switch Vault to non-dev mode (or ensure alternative secret management is secure)
- [ ] Implement proper auto-unsealing for Vault (if using Vault)

## References

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Consul Documentation](https://www.consul.io/docs)
- [Vault Documentation](https://www.vaultproject.io/docs)

## License

This project is licensed under the MIT License - see the LICENSE file for details.# Microservice Template Instructions

