#!/bin/bash

# Script to generate Traefik v3 configuration from .env file
# Usage: ./generate-traefik-config.sh

# Load environment variables from .env file
if [ -f /.env ]; then
  export $(grep -v '^#' /.env | xargs)
  echo "Loaded environment variables from /.env file"
else
  echo "Error: .env file not found!"
  exit 1
fi

# Create traefik config directory if it doesn't exist
mkdir -p ../config

# Generate static configuration for Traefik v3
cat >../config/traefik.yaml <<EOF
## Static configuration for Traefik v3
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

api:
  dashboard: ${TRAEFIK_DASHBOARD_ENABLED:-false}
  insecure: true

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
  
  consul:
    endpoints:
      - "http://consul-server:8500"
    rootKey: "${TRAEFIK_CONSUL_ROOTKEY:-traefik}"

log:
  level: "${TRAEFIK_LOG_LEVEL:-INFO}"
EOF

# If TLS is enabled, add TLS configuration
if [ "${TRAEFIK_TLS_ENABLED:-false}" = "true" ]; then
  cat >>../config/traefik.yaml <<EOF

certificatesResolvers:
  letsencrypt:
    acme:
      email: "${TRAEFIK_ACME_EMAIL:-admin@example.com}"
      storage: "/etc/traefik/acme/acme.json"
      httpChallenge:
        entryPoint: "web"
EOF
fi

# Generate middleware configurations - these remain mostly the same in v3
cat >../config/dynamic.yaml <<EOF
# Dynamic configuration (will be stored in Consul)
http:
  middlewares:
    rate-limit:
      rateLimit:
        average: ${TRAEFIK_RATE_LIMIT_AVERAGE:-100}
        burst: ${TRAEFIK_RATE_LIMIT_BURST:-50}
    
    secure-headers:
      headers:
        frameDeny: true
        browserXssFilter: true
        contentTypeNosniff: true
        stsSeconds: 31536000
        stsIncludeSubdomains: true
    
    compress:
      compress:
        excludedContentTypes:
          - "text/event-stream"
EOF

# If IP whitelist is enabled, generate IP whitelist configuration
if [ "${TRAEFIK_IP_WHITELIST_ENABLED:-false}" = "true" ]; then
  cat >>../config/dynamic.yaml <<EOF
    
    ipwhitelist:
      ipWhiteList:
        sourceRange:
          - "127.0.0.1/32"
EOF
  # Convert comma-separated IPs to YAML list
  if [ ! -z "${TRAEFIK_IP_WHITELIST:-}" ]; then
    for ip in $(echo ${TRAEFIK_IP_WHITELIST} | tr ',' '\n'); do
      echo "          - \"$ip\"" >>../config/dynamic.yaml
    done
  fi
fi

echo "Traefik v3 configuration files generated successfully!"
echo " - Static config: ../config/traefik.yaml"
echo " - Dynamic config template: ../config/dynamic.yaml"
