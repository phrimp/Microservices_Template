#!/bin/sh

# This script demonstrates how to register a service with Consul using the API
# It is useful for services that don't have Consul client integration

# Configuration (can be set via environment variables)
SERVICE_NAME=${SERVICE_NAME:-"external-service"}
SERVICE_ID=${SERVICE_ID:-"${SERVICE_NAME}-1"}
SERVICE_PORT=${SERVICE_PORT:-80}
SERVICE_ADDRESS=${SERVICE_ADDRESS:-$(hostname -i || ip route get 1 | awk '{print $NF;exit}')}
CONSUL_HTTP_ADDR=${CONSUL_HTTP_ADDR:-"consul-server:8500"}

# Wait for Consul to be available
until curl -s ${CONSUL_HTTP_ADDR}/v1/status/leader | grep -q .; do
  echo "Waiting for Consul server..."
  sleep 5
done

# Create service definition
cat >service.json <<EOF
{
  "ID": "${SERVICE_ID}",
  "Name": "${SERVICE_NAME}",
  "Address": "${SERVICE_ADDRESS}",
  "Port": ${SERVICE_PORT},
  "Tags": ["external", "v1"],
  "Meta": {
    "version": "1.0",
    "environment": "production"
  },
  "Check": {
    "HTTP": "http://${SERVICE_ADDRESS}:${SERVICE_PORT}/health",
    "Interval": "10s",
    "Timeout": "1s",
    "DeregisterCriticalServiceAfter": "30s"
  }
}
EOF

# Register service with Consul
echo "Registering service ${SERVICE_NAME} (${SERVICE_ID}) with Consul..."
REGISTER_RESULT=$(curl -s -X PUT --data @service.json ${CONSUL_HTTP_ADDR}/v1/agent/service/register)

# Check registration result
if [ -z "$REGISTER_RESULT" ]; then
  echo "Service registered successfully"
else
  echo "Error registering service: $REGISTER_RESULT"
  exit 1
fi

# Keep checking Consul and re-register if needed
echo "Starting service registration monitor..."
while true; do
  sleep 60
  SERVICE_CHECK=$(curl -s ${CONSUL_HTTP_ADDR}/v1/agent/service/${SERVICE_ID})

  if echo "$SERVICE_CHECK" | grep -q "ServiceID"; then
    echo "Service ${SERVICE_ID} still registered ($(date))"
  else
    echo "Service not registered, re-registering..."
    curl -s -X PUT --data @service.json ${CONSUL_HTTP_ADDR}/v1/agent/service/register
  fi
done
