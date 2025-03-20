#!/bin/sh

# This script monitors Docker containers and registers them with Consul
# It also transfers traefik labels from Docker to Consul tags

while true; do
  # Get a list of all running containers
  containers=$(docker ps --format '{{.Names}}')

  for container in $containers; do
    # Get container details in JSON format
    container_info=$(docker inspect $container | jq -r '.[0]')

    # Extract container IP address
    ip_address=$(echo $container_info | jq -r '.NetworkSettings.Networks | to_entries[0].value.IPAddress')

    # Extract service port from environment variables or expose
    port=$(echo $container_info | jq -r '.Config.Env[] | select(startswith("SERVICE_PORT="))' | cut -d= -f2)
    if [ -z "$port" ]; then
      port=$(echo $container_info | jq -r '.Config.ExposedPorts | keys[0]' | cut -d/ -f1)
    fi

    # Skip if no port is found
    if [ -z "$port" ]; then
      continue
    fi

    # Extract traefik labels
    traefik_labels=$(echo $container_info | jq -r '.Config.Labels | to_entries | map(select(.key | startswith("traefik."))) | map("\(.key)=\(.value)") | .[]')

    # Skip if container doesn't have traefik.enable=true
    if ! echo "$traefik_labels" | grep -q "traefik.enable=true"; then
      continue
    fi

    # Create service tags array including traefik labels
    tags_json="["
    for label in $traefik_labels; do
      tags_json="$tags_json\"$label\","
    done
    tags_json="${tags_json%,}]"

    # Create the service registration JSON
    service_json="{
      \"ID\": \"$container-docker\",
      \"Name\": \"$container\",
      \"Address\": \"$ip_address\",
      \"Port\": $port,
      \"Tags\": $tags_json,
      \"Check\": {
        \"HTTP\": \"http://$ip_address:$port/health\",
        \"Interval\": \"10s\",
        \"Timeout\": \"1s\",
        \"DeregisterCriticalServiceAfter\": \"30s\"
      }
    }"

    # Register service with Consul
    echo "Registering $container with Consul..."
    curl -s -X PUT --data "$service_json" $CONSUL_HTTP_ADDR/v1/agent/service/register
  done

  sleep 30
done
