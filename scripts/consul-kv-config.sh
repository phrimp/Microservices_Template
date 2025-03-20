#!/bin/bash

# This script demonstrates how to populate Consul's Key-Value store with configuration
# Wait for Consul to be available
until curl -s http://consul-server:8500/v1/status/leader | grep -q .; do
  echo "Waiting for Consul server..."
  sleep 5
done

# Create application configuration
echo "Setting up application configurations in Consul KV store..."

# Database configuration
curl -X PUT -d 'scylladb-cluster.internal' http://consul-server:8500/v1/kv/config/database/host
curl -X PUT -d '9042' http://consul-server:8500/v1/kv/config/database/port
curl -X PUT -d 'appuser' http://consul-server:8500/v1/kv/config/database/username

# Cache configuration
curl -X PUT -d 'redis-master.internal' http://consul-server:8500/v1/kv/config/cache/host
curl -X PUT -d '6379' http://consul-server:8500/v1/kv/config/cache/port
curl -X PUT -d '300' http://consul-server:8500/v1/kv/config/cache/default_ttl

# Message queue configuration
curl -X PUT -d 'rabbitmq.internal' http://consul-server:8500/v1/kv/config/queue/host
curl -X PUT -d '5672' http://consul-server:8500/v1/kv/config/queue/port
curl -X PUT -d 'guest' http://consul-server:8500/v1/kv/config/queue/username

# API configuration
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/config/api/enable_rate_limit
curl -X PUT -d '100' http://consul-server:8500/v1/kv/config/api/rate_limit_per_minute
curl -X PUT -d '10' http://consul-server:8500/v1/kv/config/api/max_connections

# Feature flags
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/features/new_ui
curl -X PUT -d 'false' http://consul-server:8500/v1/kv/features/beta_feature
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/features/analytics

# Traefik specific configuration
# API Gateway settings
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/config/api-gateway/enabled
curl -X PUT -d 'api.example.com' http://consul-server:8500/v1/kv/config/api-gateway/domain
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/config/api-gateway/tls/enabled
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/config/api-gateway/retry/enabled
curl -X PUT -d '3' http://consul-server:8500/v1/kv/config/api-gateway/retry/attempts
curl -X PUT -d '100ms' http://consul-server:8500/v1/kv/config/api-gateway/retry/initialInterval

# Traefik metrics settings
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/config/api-gateway/metrics/enabled
curl -X PUT -d 'prometheus' http://consul-server:8500/v1/kv/config/api-gateway/metrics/provider

# Traefik middleware chain defaults
curl -X PUT -d 'security-headers,rate-limit' http://consul-server:8500/v1/kv/config/api-gateway/default-middlewares

echo "Configuration successfully loaded into Consul KV store"
