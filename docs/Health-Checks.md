# Health Checks

Health checks are critical in a microservice architecture to ensure service availability and enable automatic recovery from failures. This page explains how to implement health checks in various components of the architecture.

## Docker Health Checks

Docker provides built-in health check capabilities to monitor container health.

### Basic Docker Health Check

In your Docker Compose file:

```yaml
services:
  my-service:
    image: my-service:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

Parameters explained:
- `test`: Command to execute to check health
- `interval`: Time between health checks
- `timeout`: Maximum time a check can take
- `retries`: Number of consecutive failures needed to mark unhealthy
- `start_period`: Grace period for startup before counting failures

### HTTP Health Check Examples

For web services:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

For services without curl:

```yaml
healthcheck:
  test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### Database Health Check Examples

MySQL:

```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
  interval: 30s
  timeout: 10s
  retries: 3
```

PostgreSQL:

```yaml
healthcheck:
  test: ["CMD", "pg_isready", "-U", "postgres"]
  interval: 30s
  timeout: 10s
  retries: 3
```

Redis:

```yaml
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 30s
  timeout: 10s
  retries: 3
```

## Consul Health Checks

Consul health checks complement Docker health checks by providing service-level monitoring and registration.

### Registering Health Checks with Consul

Health checks can be defined when registering a service:

```javascript
// Node.js example
const consul = require('consul')();

consul.agent.service.register({
  name: 'my-service',
  id: 'my-service-1',
  address: '192.168.1.100',
  port: 8080,
  check: {
    http: 'http://localhost:8080/health',
    interval: '10s',
    timeout: '5s',
    deregister_critical_service_after: '30m'
  }
});
```

### Types of Consul Health Checks

Consul supports multiple check types:

#### HTTP Checks

```json
{
  "check": {
    "http": "http://localhost:8080/health",
    "interval": "10s",
    "timeout": "5s"
  }
}
```

#### TCP Checks

```json
{
  "check": {
    "tcp": "localhost:8080",
    "interval": "10s",
    "timeout": "5s"
  }
}
```

#### Command Checks

```json
{
  "check": {
    "args": ["/scripts/check-service.sh"],
    "interval": "30s"
  }
}
```

#### TTL Checks

TTL (Time To Live) checks require the service to continually update its status:

```json
{
  "check": {
    "ttl": "60s"
  }
}
```

The service must then regularly check in:

```javascript
consul.agent.check.pass('service:my-service-1', function(err) {
  if (err) throw err;
});
```

### Multiple Checks for a Service

You can define multiple checks for comprehensive monitoring:

```javascript
consul.agent.service.register({
  name: 'my-service',
  id: 'my-service-1',
  address: '192.168.1.100',
  port: 8080,
  checks: [
    {
      http: 'http://localhost:8080/health',
      interval: '10s',
      notes: 'Basic connectivity check'
    },
    {
      http: 'http://localhost:8080/health/db',
      interval: '30s',
      notes: 'Database connectivity check'
    },
    {
      http: 'http://localhost:8080/health/external-api',
      interval: '60s',
      notes: 'External API dependency check'
    }
  ]
});
```

## Implementing Health Check Endpoints

### Basic Health Check Endpoint

A minimal health check endpoint:

```javascript
// Express.js example
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});
```

### Comprehensive Health Check

A more comprehensive check that verifies dependencies:

```javascript
// Express.js example
app.get('/health', async (req, res) => {
  try {
    // Check database connection
    const dbStatus = await checkDatabaseConnection();
    
    // Check cache connection
    const cacheStatus = await checkCacheConnection();
    
    // Check external API dependencies
    const apiStatus = await checkExternalApiStatus();
    
    const status = {
      service: 'up',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      database: dbStatus,
      cache: cacheStatus,
      externalApi: apiStatus
    };
    
    // Determine overall health
    const isHealthy = dbStatus.status === 'up' && cacheStatus.status === 'up';
    
    res
      .status(isHealthy ? 200 : 500)
      .json(status);
  } catch (error) {
    res
      .status(500)
      .json({
        service: 'down',
        error: error.message
      });
  }
});
```

### Health Check Best Practices

1. **Separate checks for different dependencies**: Create specific endpoints for different dependency types
2. **Include appropriate detail**: Provide useful information without exposing sensitive details
3. **Keep checks lightweight**: Health checks should not impact service performance
4. **Include version information**: Add version/build info to help with troubleshooting
5. **Make checks deterministic**: Results should be consistent for the same conditions

## Monitoring Health With Traefik

Traefik can route traffic based on service health:

```yaml
labels:
  - "traefik.http.services.my-service.loadbalancer.healthcheck.path=/health"
  - "traefik.http.services.my-service.loadbalancer.healthcheck.interval=10s"
  - "traefik.http.services.my-service.loadbalancer.healthcheck.timeout=5s"
```

## Viewing Health Status

### Consul UI

Access the Consul UI at http://localhost:8500 and navigate to the "Services" tab to see service health status.

### Consul API

```bash
# Get health status of all instances of a service
curl http://localhost:8500/v1/health/service/my-service

# Get only passing instances
curl http://localhost:8500/v1/health/service/my-service?passing=true

# Get detailed health check information
curl http://localhost:8500/v1/health/checks/my-service
```

### Docker Commands

```bash
# View container health status
docker ps --format "table {{.Names}}\t{{.Status}}"

# Detailed health status for a specific container
docker inspect --format "{{json .State.Health }}" my-service | jq
```

## Automated Recovery Actions

### Docker Restart Policies

```yaml
services:
  my-service:
    restart: unless-stopped
    # or
    restart: on-failure
    # or with max retries
    restart: on-failure:5
```

### Traefik Circuit Breakers

Circuit breakers prevent requests to unhealthy services:

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

## Health Check Monitoring and Alerting

For production environments, implement monitoring and alerting:

1. **Prometheus** for metrics collection:
   - Collect service health metrics
   - Set up alerts for persistent health check failures

2. **Grafana** for visualization:
   - Create dashboards for service health
   - Display health check history

3. **AlertManager** for notifications:
   - Send alerts via email, Slack, or PagerDuty
   - Implement escalation policies