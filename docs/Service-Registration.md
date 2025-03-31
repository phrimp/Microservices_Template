# Service Registration

Service registration is a critical aspect of a microservice architecture. This page explains how to register services with Consul, the service discovery component in our architecture.

## Registration Methods

There are two main ways to register services with Consul:

1. **Docker Labels**: For containerized services managed by Docker Compose
2. **Programmatic Registration**: For services that need to register themselves

## Using Docker Labels

The simplest way to register a service is to use Docker labels in your Docker Compose file. Traefik automatically registers services with these labels.

### Basic Labels

```yaml
services:
  my-service:
    image: your-image:tag
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)"
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"
      - "traefik.docker.network=microservices_template_traefik-net"

# Health check for Docker
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

Traefik will automatically register this service with Consul and set up routing based on the labels.

## Programmatic Registration

For more control, you can register services programmatically from within your application code.

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

## Verifying Service Registration

### Using the Consul UI

Visit http://localhost:8500 and check the "Services" tab to see all registered services.

### Using the Consul API

```bash
# List all services
curl http://localhost:8500/v1/catalog/services

# Get details for a specific service
curl http://localhost:8500/v1/catalog/service/my-service

# Check health of a service
curl http://localhost:8500/v1/health/service/my-service?passing
```

## Best Practices for Service Registration

1. **Always include health checks**: This allows Consul to monitor the health of your services.
2. **Use unique service IDs**: Include instance-specific information in the service ID.
3. **Implement graceful deregistration**: Services should deregister themselves when shutting down.
4. **Use meaningful tags**: Tags make it easier to filter and organize services.
5. **Keep registration metadata minimal**: Only include essential information in the service registration.