# Microservice Template Instructions

## Overview

This document provides step-by-step instructions for setting up and using the microservice architecture template. The template implements a robust, scalable microservice-based application infrastructure using modern technologies for containerization, service discovery, API gateway, monitoring, and more.

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

## Prerequisites

- Docker and Docker Compose installed
- Git installed
- Basic understanding of containerization and microservices
- Free ports as specified in the `.env` file (by default: 80, 443, 8080, 8500, 8600)

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

For production environments:
- Generate a proper Consul encryption key
- Set proper passwords and API keys
- Enable TLS
- Disable insecure dashboard access

### 2. Starting the Core Infrastructure

Start the core services (Consul and Traefik):

```bash
docker-compose up -d
```

This command starts:
- Consul server for service discovery and configuration
- Traefik as the API gateway and load balancer
- A helper container to register Traefik middleware configurations in Consul

Verify the services are running:

```bash
docker-compose ps
```

### 3. Access the Management Dashboards

- **Consul Dashboard**: http://localhost:8500
- **Traefik Dashboard**: http://localhost:8080

### 4. Adding Your First Microservice

Create a service directory:

```bash
mkdir -p services/my-service
cd services/my-service
```

Create a Docker Compose file (`docker-compose.yml`):

```yaml
version: '3'

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

Your service will now be:
- Registered with Consul for service discovery
- Available through Traefik at the configured path
- Protected by the configured middlewares

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

## Integration with Traefik

After registering your service with Consul, integrate it with Traefik by using Consul catalog configuration. Create a middleware and router configuration in Consul:

```bash
# Create a router for your service
curl -X PUT -d '{
  "http": {
    "routers": {
      "my-service-router": {
        "entryPoints": ["web"],
        "rule": "PathPrefix(`/my-service`)",
        "service": "my-service",
        "middlewares": ["rate-limit", "secure-headers"]
      }
    }
  }
}' http://consul-server:8500/v1/kv/traefik/http/routers/my-service-router

# Create a service backend for your Consul service
curl -X PUT -d '{
  "http": {
    "services": {
      "my-service": {
        "loadBalancer": {
          "servers": [
            {
              "url": "http://my-service:8080"
            }
          ]
        }
      }
    }
  }
}' http://consul-server:8500/v1/kv/traefik/http/services/my-service
```

Alternatively, use the Traefik Consul Catalog provider (already configured) which will automatically detect services registered in Consul with the appropriate tags:

```java
// When registering your service, add specific tags for Traefik
service.setTags(Arrays.asList(
    "traefik.enable=true",
    "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)",
    "traefik.http.services.my-service.loadbalancer.server.port=8080"
));
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

## Advanced Configuration

## Customizing Middleware

There are multiple ways to customize middleware in this architecture:

### 1. Using Consul KV Store

To add custom middleware configurations to Consul:

```bash
# Register a custom middleware
curl -X PUT -d '{
  "stripPrefix": {
    "prefixes": ["/api"],
    "forceSlash": false
  }
}' http://consul-server:8500/v1/kv/traefik/http/middlewares/my-strip-prefix/

# Apply it to a service using labels
# traefik.http.routers.my-service.middlewares=my-strip-prefix@consul
```

### 2. Modifying the Registration Script

For persistent middleware, modify the `register-traefik-config-to-consul.sh` script:

```bash
# Add to the script
echo "Registering custom-auth middleware..."
curl -X PUT -d '{
  "basicAuth": {
    "users": ["user:$apr1$xyz..."],
    "realm": "MyRealm"
  }
}' http://consul-server:8500/v1/kv/traefik/http/middlewares/custom-auth/
```

Then restart the registration container:

```bash
docker-compose restart traefik-consul-register
```

### 3. Programmatic Middleware Registration

You can also register middlewares programmatically from your services:

#### Java Example

```java
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.web.client.RestTemplate;
import java.util.Base64;

public class MiddlewareRegistration {
    
    public void registerMiddleware() {
        RestTemplate restTemplate = new RestTemplate();
        
        // Create middleware configuration
        String middlewareJson = "{"
            + "\"circuitBreaker\": {"
            + "  \"expression\": \"NetworkErrorRatio() > 0.5\","
            + "  \"fallbackDuration\": \"10s\""
            + "}"
            + "}";
        
        // Convert to base64 for Consul KV storage
        String encodedValue = Base64.getEncoder().encodeToString(middlewareJson.getBytes());
        
        // Prepare request
        HttpHeaders headers = new HttpHeaders();
        headers.set("Content-Type", "application/json");
        HttpEntity<String> entity = new HttpEntity<>("{\"Value\":\"" + encodedValue + "\"}", headers);
        
        // Send to Consul
        restTemplate.put(
            "http://consul-server:8500/v1/kv/traefik/http/middlewares/java-circuit-breaker", 
            entity
        );
        
        System.out.println("Middleware registered successfully");
    }
}
```

#### Node.js Example

```javascript
const axios = require('axios');

async function registerMiddleware() {
    const middlewareConfig = {
        rateLimit: {
            average: 50,
            burst: 100,
            period: "1s"
        }
    };
    
    // Consul requires Base64 encoding for values
    const encodedConfig = Buffer.from(JSON.stringify(middlewareConfig)).toString('base64');
    
    try {
        await axios.put(
            'http://consul-server:8500/v1/kv/traefik/http/middlewares/node-rate-limit',
            { Value: encodedConfig },
            { headers: { 'Content-Type': 'application/json' } }
        );
        
        console.log('Middleware registered successfully');
    } catch (error) {
        console.error('Error registering middleware:', error);
    }
}

registerMiddleware();
```

#### Golang Example

```go
package main

import (
    "bytes"
    "encoding/json"
    "fmt"
    "net/http"
)

func registerMiddleware() error {
    // Create middleware configuration
    type ipWhitelistConfig struct {
        SourceRange []string `json:"sourceRange"`
    }
    
    type middlewareConfig struct {
        IPWhiteList ipWhitelistConfig `json:"ipWhiteList"`
    }
    
    config := middlewareConfig{
        IPWhiteList: ipWhitelistConfig{
            SourceRange: []string{"192.168.1.0/24", "127.0.0.1/32"},
        },
    }
    
    // Marshal to JSON
    configBytes, err := json.Marshal(config)
    if err != nil {
        return fmt.Errorf("failed to marshal config: %v", err)
    }
    
    // Send to Consul
    req, err := http.NewRequest(
        "PUT",
        "http://consul-server:8500/v1/kv/traefik/http/middlewares/go-ip-whitelist",
        bytes.NewBuffer(configBytes),
    )
    if err != nil {
        return fmt.Errorf("failed to create request: %v", err)
    }
    
    req.Header.Set("Content-Type", "application/json")
    
    client := &http.Client{}
    resp, err := client.Do(req)
    if err != nil {
        return fmt.Errorf("failed to send request: %v", err)
    }
    defer resp.Body.Close()
    
    if resp.StatusCode != http.StatusOK {
        return fmt.Errorf("failed to register middleware: %v", resp.Status)
    }
    
    fmt.Println("Middleware registered successfully")
    return nil
}
```

#### C# Example

```csharp
using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

public class MiddlewareRegistration
{
    public async Task RegisterMiddleware()
    {
        var middlewareConfig = new
        {
            errors = new
            {
                status = new[] { "500-599" },
                service = "error-service",
                query = "/error.html"
            }
        };
        
        var jsonContent = JsonSerializer.Serialize(middlewareConfig);
        var content = new StringContent(jsonContent, Encoding.UTF8, "application/json");
        
        using var httpClient = new HttpClient();
        var response = await httpClient.PutAsync(
            "http://consul-server:8500/v1/kv/traefik/http/middlewares/dotnet-error-pages",
            content
        );
        
        if (response.IsSuccessStatusCode)
        {
            Console.WriteLine("Middleware registered successfully");
        }
        else
        {
            Console.WriteLine($"Failed to register middleware: {response.StatusCode}");
        }
    }
}
```

### 4. Using Docker Labels (for Simple Middlewares)

For some simple middlewares, you can define them directly with Docker labels:

```yaml
services:
  my-service:
    # ... other configuration
    labels:
      # Define the middleware directly
      - "traefik.http.middlewares.my-retry.retry.attempts=3"
      - "traefik.http.middlewares.my-retry.retry.initialInterval=100ms"
      # Apply it to the router
      - "traefik.http.routers.my-service.middlewares=my-retry@docker"
```

### 5. Advanced Custom Middleware (Traefik Plugins)

For more advanced use cases, Traefik supports custom plugins. These require modifying the Traefik configuration:

1. Create a plugin in Go following the Traefik plugin architecture
2. Publish it to GitHub
3. Update the Traefik static configuration to include your plugin:

```yaml
# traefik.yml
experimental:
  plugins:
    my-plugin:
      moduleName: "github.com/username/my-traefik-plugin"
      version: "v0.1.0"
```

Then use the plugin in your dynamic configuration:

```yaml
http:
  middlewares:
    my-custom-middleware:
      plugin:
        my-plugin:
          option1: value1
          option2: value2
```

### Scaling Services

Individual services can be scaled with Docker Compose:

```bash
cd services/my-service
docker-compose up -d --scale my-service=3
```

Traefik will automatically load-balance between instances.

## Troubleshooting

### Check Logs

```bash
# Check Consul logs
docker logs consul-server

# Check Traefik logs
docker logs traefik

# Check middleware registration logs
docker logs traefik-consul-register
```

### Common Issues

1. **Service not accessible through Traefik**
   - Ensure the service is in the correct network
   - Verify labels are correctly set
   - Check Traefik dashboard for routing issues

2. **Middleware not applying**
   - Verify the middleware was registered correctly in Consul
   - Check the middleware name in Traefik labels

3. **Container health checks failing**
   - Verify the service is ready to accept connections
   - Check container logs for startup issues

## Extending the Template

This template provides the core infrastructure. To fully implement the architecture described in the Project Architecture Document, consider adding:

- **RabbitMQ** for asynchronous communication
- **Linkerd** for service mesh capabilities
- **HashiCorp Vault** for secret management
- **Prometheus and Jaeger** for monitoring and tracing
- **Redis** for caching
- **MinIO** for object storage
- **ScyllaDB** for high-performance data storage

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

## References

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Consul Documentation](https://www.consul.io/docs)
