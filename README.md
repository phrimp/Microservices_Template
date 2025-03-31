# Quick Start

## Prerequisites

- Docker and Docker Compose installed
- Git installed
- Basic understanding of containerization and microservices
- Free ports as specified in the `.env` file (by default: 80, 443, 8080, 8500, 8600, 8200)

## Documentation

This microservices template provides a robust foundation for building scalable applications. The documentation is split between this README and the [project Wiki](../../wiki).

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
