storage "consul" {
  address = "consul-server:8500"
  path = "vault/"
  # token = "" # Uncomment and add token if Consul ACLs are enabled
  service = "vault"
  service_tags = "vault-server"
  service_address = "vault"  # Use the container name as the service address
  # disable_registration = true  # Uncomment this line if you want to disable service registration
}

# Use file storage for audit logs if you enable the file audit backend
# storage "file" {
#   path = "/vault/file"
# }

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = 1
}

ui = true
disable_mlock = true
api_addr = "http://vault:8200"  # Use container name instead of 0.0.0.0
cluster_addr = "http://vault:8201"  # Add cluster address

# Telemetry configuration for monitoring
telemetry {
  disable_hostname = true
  prometheus_retention_time = "30s"
}
