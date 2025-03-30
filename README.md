## Overview

This document provides step-by-step instructions for setting up and using the microservice architecture template. The template implements a robust, scalable microservice-based application infrastructure using modern technologies for containerization, service discovery, API gateway, monitoring, and more.

## Core Components

### Consul: Service Discovery and Distributed Configuration

Consul serves as the backbone of our microservice architecture, providing:

- **Service Discovery**: Enables microservices to find and communicate with each other without hardcoded addresses
- **Health Checking**: Continuously monitors service health to ensure availability and facilitate failover
- **Key-Value Store**: Centralized configuration storage that all services can access
- **Dynamic Configuration**: Allows real-time updates to service configurations without restarts
- **DNS-based Service Discovery**: Services can be discovered via simple DNS queries
- **Service Mesh Capabilities**: Provides a foundation for advanced service-to-service communication patterns

In this implementation, Consul:
- Maintains the service registry for all microservices
- Stores Traefik's dynamic configurations including middleware definitions
- Provides health status information for all registered services
- Enables dynamic reconfiguration of the entire system
- Acts as the source of truth for service locations and configurations

### Traefik: Modern API Gateway and Edge Router

Traefik functions as the entry point and traffic manager for the system:

- **Automatic Service Discovery**: Integrates with Consul to dynamically discover backend services
- **Middleware Pipeline**: Processes requests through configurable middleware chains
- **Dynamic Configuration**: Updates routing rules on-the-fly without restarts
- **Let's Encrypt Integration**: Automatic SSL certificate provisioning and renewal
- **Circuit Breaking**: Prevents cascading failures across services
- **Request Routing**: Directs traffic to appropriate services based on paths, headers, and other criteria

In this implementation, Traefik:
- Routes external client requests to appropriate internal microservices
- Applies middleware for security, rate limiting, and request modification
- Handles SSL termination for secure communication
- Provides load balancing across service instances
- Exposes a dashboard for monitoring and troubleshooting
- Fetches configuration dynamically from Consul

### HashiCorp Vault: Secret Management and Security

Vault provides enterprise-grade security features for the microservice ecosystem:

- **Secure Secret Storage**: Centralized repository for all sensitive information
- **Dynamic Secrets**: Generate temporary credentials with automatic expiration
- **Encryption as a Service**: Provide encryption capabilities without exposing keys
- **Identity-based Access**: Fine-grained control over who can access which secrets
- **Credential Rotation**: Automatic rotation of credentials to enhance security
- **Audit Logging**: Comprehensive logs of all secret access attempts

In this implementation, Vault:
- Securely stores API keys, database credentials, and other sensitive information
- Provides dynamic access credentials to services based on their identity
- Implements the AppRole auth method for service-to-service authentication
- Maintains policies that control which services can access which secrets
- Uses Consul as its storage backend for high availability
- Automates the loading of secrets from configuration files

## Architecture Flow

### Request Flow

1. **Client Request**: A client makes an HTTP/HTTPS request to the system.
2. **Traefik Processing**:
   - The request hits Traefik, which acts as the API gateway and entry point.
   - Traefik has already loaded routing rules and middleware configurations from Consul.
   - Traefik applies configured middlewares (rate limiting, authentication, etc.) directly to the request.
3. **Request Forwarding**: After middleware processing, Traefik forwards the request to the appropriate microservice based on routing rules.
4. **Service Response**: The microservice processes the request and returns a response.
5. **Response Delivery**: Traefik forwards the response back to the client, potentially applying response middlewares.

### Service Registration Flow

1. **Service Startup**: When a microservice starts, it registers itself with Consul either:
   - Automatically via Docker labels (for containerized services)
   - Programmatically via Consul API (for services implementing direct registration)
2. **Health Checks**: Consul performs regular health checks to ensure the service is operational.
3. **Service Discovery**: Traefik and other services discover services through Consul's catalog or KV store.

### Service-to-Service Communication

1. **Service Discovery**: Microservice A queries Consul to discover the location of Microservice B.
2. **Direct Communication**: After discovery, Microservice A communicates directly with Microservice B.
3. **Communication Methods**:
   - REST/HTTP calls between services
   - gRPC for more efficient service-to-service communication
   - Event-based communication via message brokers (e.g., RabbitMQ)

Services do not communicate through Consul itself; they use Consul only to discover where other services are located. The actual communication happens directly between services.

### Configuration Flow

1. **Infrastructure Setup**: When the infrastructure starts, middleware configurations are registered in Consul KV store.
2. **Traefik Configuration**: 
   - Traefik loads initial configurations from Consul.
   - Traefik watches for changes to configurations in Consul and updates dynamically.
3. **Middleware Application**: 
   - Middlewares are configured in Consul and applied by Traefik during request processing.
   - Microservices reference these middlewares using labels or tags.
   - The actual middleware logic executes within Traefik, not as separate services.

### Secret Management Flow

1. **Vault Initialization**: On first startup, Vault is initialized and unsealed with encryption keys securely stored.
2. **Secret Loading**: Predefined secrets are loaded into Vault's key-value store.
3. **Service Authentication**: Microservices authenticate to Vault using the AppRole method.
4. **Secret Access**: 
   - Services request specific secrets they need from Vault.
   - Vault checks policies to ensure the service has appropriate access rights.
   - If approved, Vault provides the requested secrets to the service.
5. **Secret Rotation**: Credentials can be automatically rotated without service disruption.

## Prerequisites

- Docker and Docker Compose installed
- Git installed
- Basic understanding of containerization and microservices
- Free ports as specified in the `.env` file (by default: 80, 443, 8080, 8500, 8600, 8200)

## Quick Start

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

## Advanced Consul Capabilities

### Distributed Configuration

Consul can centralize your application configuration:

```bash
# Store a configuration value
curl -X PUT -d 'production' http://localhost:8500/v1/kv/environments/current

# Retrieve it from a service
consul_client.KV.get('environments/current', function(err, data) {
  const environment = data.Value;
  // Use the configuration value
});
```

### Service Dependency Management

Define relationships between services in Consul:

```bash
# Register service with dependencies
consul_client.agent.service.register({
  name: 'payment-service',
  dependencies: ['database-service', 'auth-service']
});
```

### Cross-DC Federation

For multi-region deployments, Consul supports federation:

```bash
# In docker-compose.yml for a second datacenter
consul-server-dc2:
  environment:
    - CONSUL_LOCAL_CONFIG={"datacenter":"dc2","retry_join_wan":["consul-server-dc1"]}
```

## Advanced Traefik Features

### Advanced Middleware Chains

Create complex request processing pipelines:

```yaml
# In Consul KV or via Docker labels
traefik.http.middlewares.auth-chain.chain.middlewares=rate-limit,secure-headers,basic-auth
traefik.http.routers.my-service.middlewares=auth-chain@consul
```

### Traffic Mirroring

Test new service versions without affecting users:

```yaml
# Mirror traffic to a canary service
traefik.http.middlewares.mirror-to-canary.mirror.service=my-service-canary
traefik.http.middlewares.mirror-to-canary.mirror.maxBodySize=5M
```

### Circuit Breaking

Prevent cascading failures with circuit breakers:

```yaml
# Define circuit breaker in Consul
curl -X PUT -d '{
  "circuitBreaker": {
    "expression": "NetworkErrorRatio() > 0.5"
  }
}' http://consul-server:8500/v1/kv/traefik/http/middlewares/my-circuit-breaker/
```

## Secret Loading

### Example Secret File

Create a JSON file in the `/vault/secrets` directory (mapped to `./vault/secrets` in the host) with your secrets:

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
  "encryption_key": "ahF8jUxVs9WrPzX6bQnT7EcRdL2mY5Kg",
  "read_replica": {
    "host": "db-replica.example.com",
    "port": 5432,
    "max_connections": 10
  },
  "api_credentials": {
    "key": "api-key-7f8s9d7f98sd7f98sdf",
    "secret": "api-secret-8s9df87s9d8f7s9d8f7"
  }
}
```

### Directory Structure

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

### Accessing Loaded Secrets

Once loaded, secrets will be available in Vault at paths like:
- `kv/data/services/database/prod-db`
- `kv/data/services/api/google-api`

Your services can access these using the Vault client libraries or HTTP API as shown in the examples below.

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

### Transit Encryption Engine

Encrypt data without handling encryption keys:

```bash
# Enable the transit engine
vault secrets enable transit

# Create a named encryption key
vault write -f transit/keys/my-key

# Encrypt data
curl -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
  --data '{"plaintext":"SGVsbG8gV29ybGQ="}' \
  http://vault:8200/v1/transit/encrypt/my-key
```

### Response Wrapping

Securely transmit secrets between services:

```bash
# Wrap a secret for secure transmission
curl -X POST -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "X-Vault-Wrap-TTL: 300" \
  http://vault:8200/v1/kv/data/secret-path

# The recipient unwraps to get the actual secret
curl -X POST -H "X-Vault-Token: $RECIPIENT_TOKEN" \
  --data '{"token":"WRAP_TOKEN"}' \
  http://vault:8200/v1/sys/wrapping/unwrap
```

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

## Programmatically Registering Services with Consul

In addition to Docker labels, you can register services programmatically using Consul's HTTP API from your application code.

### Java (with Spring Cloud Consul)

Add the dependencies to your `pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-starter-consul-discovery</artifactId>
</dependency>
```

Configure your `application.yml`:

```yaml
spring:
  application:
    name: my-java-service
  cloud:
    consul:
      host: consul-server
      port: 8500
      discovery:
        instanceId: ${spring.application.name}:${random.value}
        healthCheckPath: /actuator/health
        healthCheckInterval: 10s
```

Enable discovery in your main application class:

```java
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cloud.client.discovery.EnableDiscoveryClient;

@SpringBootApplication
@EnableDiscoveryClient
public class MyServiceApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyServiceApplication.class, args);
    }
}
```

### Node.js (with Consul)

Install the Consul package:

```bash
npm install consul
```

Register your service:

```javascript
const Consul = require('consul');

// Initialize Consul client
const consul = new Consul({
  host: 'consul-server',
  port: 8500
});

// Service definition
const serviceDefinition = {
  name: 'my-node-service',
  id: `my-node-service-${process.pid}`,
  address: process.env.SERVICE_HOST || '127.0.0.1',
  port: parseInt(process.env.SERVICE_PORT || 3000),
  tags: ['node', 'web'],
  check: {
    http: `http://${process.env.SERVICE_HOST || '127.0.0.1'}:${process.env.SERVICE_PORT || 3000}/health`,
    interval: '10s',
    timeout: '5s'
  }
};

// Register service
consul.agent.service.register(serviceDefinition, (err) => {
  if (err) {
    console.error('Error registering service:', err);
    return;
  }
  console.log('Service registered successfully');
});

// Handle shutdown to deregister service
process.on('SIGINT', () => {
  consul.agent.service.deregister(serviceDefinition.id, () => {
    console.log('Service deregistered');
    process.exit();
  });
});
```

### Golang (with Consul API)

Install the Consul API package:

```bash
go get github.com/hashicorp/consul/api
```

Register your service:

```go
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/hashicorp/consul/api"
)

func main() {
	// Create Consul client
	config := api.DefaultConfig()
	config.Address = "consul-server:8500"
	client, err := api.NewClient(config)
	if err != nil {
		log.Fatalf("Error creating Consul client: %s", err)
	}

	// Service registration
	serviceID := "my-go-service-1"
	service := &api.AgentServiceRegistration{
		ID:      serviceID,
		Name:    "my-go-service",
		Tags:    []string{"go", "api"},
		Port:    8080,
		Address: "127.0.0.1",
		Check: &api.AgentServiceCheck{
			HTTP:     "http://127.0.0.1:8080/health",
			Interval: "10s",
			Timeout:  "5s",
		},
	}

	// Register service
	if err := client.Agent().ServiceRegister(service); err != nil {
		log.Fatalf("Error registering service: %s", err)
	}
	fmt.Println("Service registered successfully")

	// Handle graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	// Deregister service on shutdown
	if err := client.Agent().ServiceDeregister(serviceID); err != nil {
		log.Fatalf("Error deregistering service: %s", err)
	}
	fmt.Println("Service deregistered")
}
```

### C# (.NET with Consul)

Install the Consul package:

```bash
dotnet add package Consul
```

Register your service:

```csharp
using Consul;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using System;

public static class ServiceRegistrationExtension
{
    public static IServiceCollection AddConsul(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddSingleton<IConsulClient, ConsulClient>(p => new ConsulClient(consulConfig =>
        {
            consulConfig.Address = new Uri("http://consul-server:8500");
        }));
        
        return services;
    }

    public static IApplicationBuilder UseConsul(this IApplicationBuilder app, IHostApplicationLifetime lifetime)
    {
        var consulClient = app.ApplicationServices.GetRequiredService<IConsulClient>();
        var logger = app.ApplicationServices.GetRequiredService<ILogger<IApplicationBuilder>>();
        var hostingEnv = app.ApplicationServices.GetRequiredService<IWebHostEnvironment>();
        
        // Get server IP address
        var hostName = Environment.GetEnvironmentVariable("SERVICE_HOST") ?? "127.0.0.1";
        var port = int.Parse(Environment.GetEnvironmentVariable("SERVICE_PORT") ?? "5000");
        
        var serviceId = $"my-dotnet-service-{hostName}-{port}";
        
        // Register service with Consul
        var registration = new AgentServiceRegistration()
        {
            ID = serviceId,
            Name = "my-dotnet-service",
            Address = hostName,
            Port = port,
            Tags = new[] { "dotnet", "api" },
            Check = new AgentServiceCheck()
            {
                HTTP = $"http://{hostName}:{port}/health",
                Interval = TimeSpan.FromSeconds(10),
                Timeout = TimeSpan.FromSeconds(5)
            }
        };

        logger.LogInformation("Registering with Consul");
        consulClient.Agent.ServiceRegister(registration).GetAwaiter().GetResult();
        
        // Handle application shutdown
        lifetime.ApplicationStopping.Register(() => {
            logger.LogInformation("Deregistering from Consul");
            consulClient.Agent.ServiceDeregister(serviceId).GetAwaiter().GetResult();
        });
        
        return app;
    }
}

// In Program.cs or Startup.cs
public class Startup
{
    public void ConfigureServices(IServiceCollection services)
    {
        // Other service configurations
        services.AddConsul(Configuration);
    }
    
    public void Configure(IApplicationBuilder app, IHostApplicationLifetime lifetime)
    {
        // Other app configurations
        app.UseConsul(lifetime);
    }
}
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

