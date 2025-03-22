#!/bin/bash

# Script to register Traefik's dynamic configuration in Consul from the generated config file
# Usage: ./register-traefik-config-to-consul.sh

echo "Waiting for Consul to be ready..."
until curl -s http://consul-server:8500/v1/status/leader | grep -q .; do
  sleep 5
done
echo "Consul is ready."

# Check if the dynamic config file exists
if [ ! -f "../config/dynamic.yaml" ]; then
  echo "Error: dynamic.yaml not found. Run generate-traefik-config.sh first."
  exit 1
fi

# Parse the YAML file and register each middleware in Consul
# This is a simplified approach - for complex YAML parsing, you might need a proper YAML parser
echo "Registering Traefik middleware configurations in Consul KV store..."

# Rate limiting middleware
if grep -q "rate-limit:" ../config/dynamic.yaml; then
  echo "Registering rate-limit middleware..."
  AVERAGE=$(grep -A2 "rateLimit:" ../config/dynamic.yaml | grep "average:" | awk '{print $2}')
  BURST=$(grep -A3 "rateLimit:" ../config/dynamic.yaml | grep "burst:" | awk '{print $2}')

  curl -X PUT -d '{
    "rate": {
      "average": '$AVERAGE',
      "burst": '$BURST'
    }
  }' http://consul-server:8500/v1/kv/traefik/http/middlewares/rate-limit/rateLimit
fi

# Secure headers middleware
if grep -q "secure-headers:" ../config/dynamic.yaml; then
  echo "Registering secure-headers middleware..."
  curl -X PUT -d '{
    "frameDeny": true,
    "browserXssFilter": true,
    "contentTypeNosniff": true,
    "stsSeconds": 31536000,
    "stsIncludeSubdomains": true
  }' http://consul-server:8500/v1/kv/traefik/http/middlewares/secure-headers/headers
fi

# Compression middleware
if grep -q "compress:" ../config/dynamic.yaml; then
  echo "Registering compress middleware..."
  curl -X PUT -d '{
    "excludedContentTypes": [
      "text/event-stream"
    ]
  }' http://consul-server:8500/v1/kv/traefik/http/middlewares/compress/compress
fi

# Basic authentication middleware
if grep -q "basic-auth:" ../config/dynamic.yaml; then
  echo "Registering basic-auth middleware..."
  USER_LINE=$(grep -A3 "basicAuth:" ../config/dynamic.yaml | grep "-" | sed 's/^[ \t]*-[ \t]*//')

  curl -X PUT -d '{
    "users": [
      "'$USER_LINE'"
    ]
  }' http://consul-server:8500/v1/kv/traefik/http/middlewares/basic-auth/basicAuth
fi

# IP whitelist middleware
if grep -q "ipwhitelist:" ../config/dynamic.yaml; then
  echo "Registering ipwhitelist middleware..."

  # Extract IP ranges - this is a simplified approach
  IP_RANGES=$(grep -A 100 "sourceRange:" ../config/dynamic.yaml | grep -v "sourceRange:" | grep "^[ \t]*-" | sed 's/^[ \t]*-[ \t]*//' | sed 's/"//g' | tr '\n' ',' | sed 's/,$//')

  # Convert to JSON array format
  IFS=',' read -ra IPS <<<"$IP_RANGES"
  JSON_IPS="["
  for ip in "${IPS[@]}"; do
    JSON_IPS+="\"$ip\","
  done
  JSON_IPS=${JSON_IPS%,} # Remove trailing comma
  JSON_IPS+="]"

  curl -X PUT -d '{
    "sourceRange": '$JSON_IPS'
  }' http://consul-server:8500/v1/kv/traefik/http/middlewares/ipwhitelist/ipWhiteList
fi

echo "Traefik configuration has been successfully registered in Consul."
