# Advanced Features

This page covers advanced features and capabilities of the core components in our microservice architecture. These features can enhance your implementation for specific use cases.

## Advanced Consul Features

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

### Multi-DC Federation

For multi-region deployments, Consul supports federation:

```yaml
# In docker-compose.yml for a second datacenter
consul-server-dc2:
  environment:
    - CONSUL_LOCAL_CONFIG={"datacenter":"dc2","retry_join_wan":["consul-server-dc1"]}
```

### ACL System

Enable the ACL system for production:

```yaml
services:
  consul-server:
    environment:
      - CONSUL_ACL_ENABLED=true
      - CONSUL_ACL_DEFAULT_POLICY=deny
      - CONSUL_ACL_DOWN_POLICY=extend-cache
      - CONSUL_ACL_TOKENS_MASTER=your-master-token-here
```

Then create policies and tokens:

```bash
# Create policy
consul acl policy create -name "service-policy" -rules @service-policy.hcl

# Create token bound to policy
consul acl token create -description "service token" -policy-name "service-policy"
```

### Prepared Queries

Create resilient service lookup mechanisms:

```bash
curl -X POST -d '{
  "Name": "database",
  "Service": {
    "Service": "database",
    "Failover": {
      "NearestN": 3,
      "Datacenters": ["dc2", "dc3"]
    }
  }
}' http://localhost:8500/v1/query
```

## Advanced Traefik Features

### Traffic Mirroring

Test new service versions without affecting users:

```yaml
# Mirror traffic to a canary service
labels:
  - "traefik.http.middlewares.mirror-to-canary.mirror.service=my-service-canary"
  - "traefik.http.middlewares.mirror-to-canary.mirror.maxBodySize=5M"
  - "traefik.http.routers.my-service.middlewares=mirror-to-canary"
```

### Advanced Middleware Chains

Create complex request processing pipelines:

```yaml
# Define chain in Consul
curl -X PUT -d '{
  "chain": {
    "middlewares": ["rate-limit", "secure-headers", "auth"]
  }
}' http://consul-server:8500/v1/kv/traefik/http/middlewares/auth-chain/

# Use the chain
labels:
  - "traefik.http.routers.my-service.middlewares=auth-chain@consul"
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

### Canary Deployments

Implement canary deployments with weighted routing:

```yaml
labels:
  - "traefik.http.services.my-service.weighted.services.my-service-main.weight=90"
  - "traefik.http.services.my-service.weighted.services.my-service-canary.weight=10"
```

### Active Health Checks

Configure active health checks:

```yaml
labels:
  - "traefik.http.services.my-service.loadbalancer.healthcheck.path=/health"
  - "traefik.http.services.my-service.loadbalancer.healthcheck.interval=10s"
  - "traefik.http.services.my-service.loadbalancer.healthcheck.timeout=5s"
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

### Auto-Unsealing

Configure auto-unsealing for production:

```hcl
# In vault.hcl
seal "awskms" {
  region     = "us-west-2"
  kms_key_id = "alias/vault-unseal-key"
}
```

### Lease Management

Manage and renew secret leases:

```javascript
// Get dynamic credentials with lease
const creds = await vault.read('database/creds/readonly');
const leaseId = creds.lease_id;

// Renew lease
await vault.write('sys/leases/renew', {
  lease_id: leaseId,
  increment: 3600 // renew for 1 hour
});
```

## Docker Compose Advanced Features

### Multiple Environment Support

Create environment-specific compose files:

```bash
# Base file: docker-compose.yml
# Dev overrides: docker-compose.dev.yml
# Prod overrides: docker-compose.prod.yml

# Start dev environment
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Start prod environment
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### Resource Constraints

Limit resources for containers:

```yaml
services:
  my-service:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

### Scaling Services

Scale services horizontally:

```bash
# Start multiple instances
docker-compose up -d --scale my-service=3
```

Make sure your service is configured to support scaling:

```yaml
services:
  my-service:
    image: my-service:latest
    deploy:
      mode: replicated
      replicas: 3
    labels:
      # Traefik will load balance between instances
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"
```

## Service Mesh with Linkerd

While not included in the core setup, you can add Linkerd for advanced service mesh capabilities:

### Installation

```bash
# Add Linkerd to your environment
curl -sL run.linkerd.io/install | sh

# Add Linkerd to your Kubernetes cluster
linkerd install | kubectl apply -f -
```

### Service Annotation

```yaml
annotations:
  linkerd.io/inject: enabled
```

### Features

- Automatic mTLS encryption
- Advanced traffic management
- Detailed service metrics
- Runtime debugging
- Transparent proxy (no code changes required)

## RabbitMQ for Event-Driven Architecture

Add RabbitMQ for asynchronous communication:

```yaml
services:
  rabbitmq:
    image: rabbitmq:3-management
    container_name: rabbitmq
    ports:
      - "5672:5672"
      - "15672:15672"
    environment:
      - RABBITMQ_DEFAULT_USER=guest
      - RABBITMQ_DEFAULT_PASS=guest
    volumes:
      - rabbitmq-data:/var/lib/rabbitmq
    networks:
      - traefik-net
      - consul-net

volumes:
  rabbitmq-data:
```

### Usage Patterns

- Event-driven architecture
- Work queue distribution
- Request-response via temporary queues
- Pub/sub messaging
- Dead letter queues for error handling

## Distributed Tracing with Jaeger

Add distributed tracing to understand request flows:

```yaml
services:
  jaeger:
    image: jaegertracing/all-in-one:latest
    container_name: jaeger
    ports:
      - "16686:16686"  # UI
      - "14268:14268"  # Collector HTTP
      - "6831:6831/udp"  # Agent
    environment:
      - COLLECTOR_ZIPKIN_HTTP_PORT=9411
    networks:
      - traefik-net
      - consul-net
```

### Service Instrumentation

```javascript
// Node.js example with OpenTelemetry
const { NodeTracerProvider } = require('@opentelemetry/node');
const { JaegerExporter } = require('@opentelemetry/exporter-jaeger');
const { BatchSpanProcessor } = require('@opentelemetry/tracing');

const provider = new NodeTracerProvider();
const exporter = new JaegerExporter({
  serviceName: 'my-service',
  endpoint: 'http://jaeger:14268/api/traces'
});

provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();
```

## Monitoring with Prometheus and Grafana

Add comprehensive monitoring:

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
    ports:
      - "9090:9090"
    networks:
      - traefik-net
      - consul-net

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3000:3000"
    networks:
      - traefik-net
      - consul-net

volumes:
  prometheus-data:
  grafana-data:
```

## Implementing These Advanced Features

When implementing these advanced features:

1. **Start simple**: Add features incrementally as your needs grow
2. **Test thoroughly**: Advanced features often require careful testing
3. **Document usage**: Create clear documentation for your team
4. **Monitor impact**: Advanced features may impact performance
5. **Consider security**: Each additional component expands your attack surface