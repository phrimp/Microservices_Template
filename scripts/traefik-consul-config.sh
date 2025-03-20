#!/bin/bash

# This script sets up Traefik-specific configuration in Consul's KV store
# Wait for Consul to be available
until curl -s http://consul-server:8500/v1/status/leader | grep -q .; do
  echo "Waiting for Consul server..."
  sleep 5
done

echo "Setting up Traefik configuration in Consul KV store..."

# Traefik provider configuration
curl -X PUT -d 'web,websecure' http://consul-server:8500/v1/kv/traefik/entrypoints/default
curl -X PUT -d 'true' http://consul-server:8500/v1/kv/traefik/exposedByDefault

# Middleware configurations
# Rate limit configuration for API
cat >ratelimit.json <<EOF
{
  "http": {
    "middlewares": {
      "api-ratelimit": {
        "rateLimit": {
          "average": 100,
          "burst": 50,
          "period": "1m"
        }
      }
    }
  }
}
EOF
curl -X PUT --data-binary @ratelimit.json http://consul-server:8500/v1/kv/traefik/http/middlewares

# Circuit breaker configuration
cat >circuitbreaker.json <<EOF
{
  "http": {
    "middlewares": {
      "default-circuit-breaker": {
        "circuitBreaker": {
          "expression": "NetworkErrorRatio() > 0.10 || ResponseCodeRatio(500, 600, 0, 600) > 0.25"
        }
      }
    }
  }
}
EOF
curl -X PUT --data-binary @circuitbreaker.json http://consul-server:8500/v1/kv/traefik/http/middlewares/circuitbreaker

# Security headers configuration
cat >securityheaders.json <<EOF
{
  "http": {
    "middlewares": {
      "security-headers": {
        "headers": {
          "frameDeny": true,
          "browserXssFilter": true,
          "contentTypeNosniff": true,
          "forceSTSHeader": true,
          "stsIncludeSubdomains": true,
          "stsPreload": true,
          "stsSeconds": 31536000
        }
      }
    }
  }
}
EOF
curl -X PUT --data-binary @securityheaders.json http://consul-server:8500/v1/kv/traefik/http/middlewares/security

# Default TLS configuration
cat >tls.json <<EOF
{
  "tls": {
    "options": {
      "default": {
        "minVersion": "VersionTLS12",
        "cipherSuites": [
          "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384",
          "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384",
          "TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305",
          "TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305",
          "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256",
          "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
        ],
        "sniStrict": true
      }
    }
  }
}
EOF
curl -X PUT --data-binary @tls.json http://consul-server:8500/v1/kv/traefik/tls

echo "Traefik configuration successfully loaded into Consul KV store"
