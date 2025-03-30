# Service Routing with Traefik

Traefik serves as the API gateway and load balancer in this architecture. This page explains how to configure routing for your services using Traefik Docker labels.

## Basic Routing Configuration

Traefik uses Docker labels to create routing rules. Here are the basic labels you need to add to your service:

```yaml
services:
  my-service:
    # ... other configuration
    labels:
      - "traefik.enable=true"  # Enable Traefik for this container
      - "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)"  # Route based on path
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"  # Container port
      - "traefik.docker.network=microservices_template_traefik-net"  # Docker network
```

## Path Prefixes and Stripping

Often, you want to strip the prefix before forwarding the request to your service:

```yaml
labels:
  - "traefik.http.middlewares.strip-my-service-prefix.stripprefix.prefixes=/my-service"
  - "traefik.http.routers.my-service.middlewares=strip-my-service-prefix"
```

With this configuration:
- A request to `/my-service/api/users` will be forwarded to your service as `/api/users`
- Your service doesn't need to know about the `/my-service` prefix

## Applying Middlewares

Middlewares modify requests before they reach your service or responses before they're sent back to the client.

### Using Pre-configured Middlewares from Consul

```yaml
labels:
  - "traefik.http.routers.my-service.middlewares=rate-limit@consul,secure-headers@consul"
```

The template pre-configures several middlewares in Consul:

- `rate-limit@consul`: Limits the number of requests per time period
- `secure-headers@consul`: Adds security headers to responses
- `compress@consul`: Compresses responses

### Creating Your Own Middlewares

You can define custom middlewares directly in your Docker labels:

```yaml
labels:
  # Basic Authentication
  - "traefik.http.middlewares.my-auth.basicauth.users=admin:$$apr1$$H6uskkkW$$IgXLP6ewTrSuBkTrqE8wj/"
  
  # Redirect HTTP to HTTPS
  - "traefik.http.middlewares.https-redirect.redirectscheme.scheme=https"
  - "traefik.http.middlewares.https-redirect.redirectscheme.permanent=true"
  
  # Apply the middlewares
  - "traefik.http.routers.my-service.middlewares=my-auth,https-redirect"
```

## HTTPS Configuration

To enable HTTPS for your service:

```yaml
labels:
  - "traefik.http.routers.my-service.tls=true"
  - "traefik.http.routers.my-service.tls.certresolver=letsencrypt"
```

The template is pre-configured to use Let's Encrypt for automatic certificate issuance.

## Advanced Routing Rules

Traefik supports complex routing rules:

### Multiple Path Prefixes

```yaml
labels:
  - "traefik.http.routers.my-service.rule=PathPrefix(`/api`) || PathPrefix(`/docs`)"
```

### Host-Based Routing

```yaml
labels:
  - "traefik.http.routers.my-service.rule=Host(`api.example.com`)"
```

### Combining Path and Host Rules

```yaml
labels:
  - "traefik.http.routers.my-service.rule=Host(`example.com`) && PathPrefix(`/api`)"
```

### Header-Based Routing

```yaml
labels:
  - "traefik.http.routers.my-service.rule=Headers(`X-Custom-Header`, `value`)"
```

### Query Parameter Routing

```yaml
labels:
  - "traefik.http.routers.my-service.rule=Query(`version`, `v1`)"
```

## Load Balancing

Traefik automatically load balances between multiple instances of the same service:

```yaml
services:
  my-service:
    # ... other configuration
    deploy:
      replicas: 3
```

## Circuit Breaking

Prevent cascading failures with circuit breakers:

```yaml
# Define circuit breaker in Consul
curl -X PUT -d '{
  "circuitBreaker": {
    "expression": "NetworkErrorRatio() > 0.5"
  }
}' http://consul-server:8500/v1/kv/traefik/http/middlewares/my-circuit-breaker/

# Reference in your service
labels:
  - "traefik.http.routers.my-service.middlewares=my-circuit-breaker@consul"
```

## Traffic Mirroring

Test new service versions without affecting users:

```yaml
# Mirror traffic to a canary service
labels:
  - "traefik.http.middlewares.mirror-to-canary.mirror.service=my-service-canary"
  - "traefik.http.middlewares.mirror-to-canary.mirror.maxBodySize=5M"
  - "traefik.http.routers.my-service.middlewares=mirror-to-canary"
```

## Middleware Chains

Create complex request processing pipelines:

```yaml
# Define a chain of middlewares
labels:
  - "traefik.http.middlewares.auth-chain.chain.middlewares=rate-limit@consul,secure-headers@consul,my-auth"
  - "traefik.http.routers.my-service.middlewares=auth-chain"
```

## Verifying Routing Configuration

To verify your routing configuration, check the Traefik dashboard at http://localhost:8080. It shows:

- Configured routers
- Middleware chains
- Service endpoints
- Health status

## Best Practices

1. **Use namespaced router names**: Include your service name in router names to avoid conflicts
2. **Keep middleware chains short**: Long chains can impact performance
3. **Test routing rules thoroughly**: Ensure rules match the expected paths
4. **Use circuit breakers for critical services**: Prevent cascading failures
5. **Monitor Traefik metrics**: Watch for unusual patterns or errors