#!/bin/bash

# Script to generate Consul configuration from .env file
# Usage: ./generate-consul-config.sh

# Load environment variables from .env file
if [ -f /.env ]; then
  export $(grep -v '^#' /.env | xargs)
  echo "Loaded environment variables from /.env file"
else
  echo "Error: .env file not found!"
  exit 1
fi

# Create consul config directory if it doesn't exist
mkdir -p ../config

# Generate server config JSON
cat >../config/server.json <<EOF
{
  "datacenter": "${CONSUL_DATACENTER:-dc1}",
  "data_dir": "/consul/data",
  "log_level": "${CONSUL_LOG_LEVEL:-INFO}",
  "server": true,
  "ui_config": {
    "enabled": true
  },
  "bind_addr": "0.0.0.0",
  "client_addr": "0.0.0.0",
  "bootstrap_expect": 1,
  "node_name": "consul-server",
  "ports": {
    "http": 8500,
    "dns": 8600
  }
}
EOF

# If encryption is enabled, add the encryption key
if [ ! -z "$CONSUL_ENCRYPT_KEY" ]; then
  # Use jq to add the encrypt key (install jq if not available)
  if command -v jq &>/dev/null; then
    jq --arg key "$CONSUL_ENCRYPT_KEY" '. + {"encrypt": $key}' ../config/server.json >../config/server.json.tmp
    mv ../config/server.json.tmp ../config/server.json
  else
    echo "Warning: jq not installed, skipping encryption key configuration"
  fi
fi

# If ACL is enabled, add ACL configuration
if [ "${CONSUL_ACL_ENABLED:-false}" = "true" ]; then
  cat >../config/acl.json <<EOF
{
  "acl": {
    "enabled": true,
    "default_policy": "${CONSUL_ACL_DEFAULT_POLICY:-deny}",
    "down_policy": "${CONSUL_ACL_DOWN_POLICY:-extend-cache}",
    "tokens": {
      "master": "${CONSUL_ACL_TOKENS_MASTER}"
    }
  }
}
EOF
fi

# Generate client config JSON for other services
cat >../config/client.json <<EOF
{
  "datacenter": "${CONSUL_DATACENTER:-dc1}",
  "data_dir": "/consul/data",
  "log_level": "${CONSUL_LOG_LEVEL:-INFO}",
  "server": false,
  "bind_addr": "0.0.0.0",
  "client_addr": "0.0.0.0",
  "retry_join": ["${CONSUL_RETRY_JOIN:-consul-server}"],
  "enable_script_checks": ${CONSUL_ENABLE_SCRIPT_CHECKS:-true},
  "enable_local_script_checks": ${CONSUL_ENABLE_LOCAL_SCRIPT_CHECKS:-true}
}
EOF

echo "Consul configuration files generated successfully!"
echo " - Server config: ../config/server.json"
echo " - Client config: ../config/client.json"
if [ "${CONSUL_ACL_ENABLED:-false}" = "true" ]; then
  echo " - ACL config: ../config/acl.json"
fi
