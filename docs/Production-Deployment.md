# Production Deployment

This page provides guidance on preparing and deploying the microservices architecture to a production environment. Production environments require additional considerations for security, reliability, and performance.

## Production Deployment Checklist

Before deploying to production, ensure you've addressed the following items:

- [ ] Generate new encryption keys and passwords
- [ ] Enable TLS for all services
- [ ] Secure all admin interfaces
- [ ] Set up proper backup procedures
- [ ] Configure monitoring and alerting
- [ ] Implement proper logging
- [ ] Test failover scenarios
- [ ] Document the deployment process
- [ ] Enable Consul ACLs
- [ ] Switch Vault to non-dev mode
- [ ] Implement proper auto-unsealing for Vault

## Environment Configuration

Update your `.env` file with production-appropriate settings:

```ini
# Consul Production Settings
CONSUL_LOG_LEVEL=WARN
CONSUL_DATACENTER=production
CONSUL_ENCRYPT_KEY=<generate-new-key>
CONSUL_ACL_ENABLED=true
CONSUL_ACL_DEFAULT_POLICY=deny
CONSUL_ACL_DOWN_POLICY=extend-cache
CONSUL_ACL_TOKENS_MASTER=<generate-secure-token>

# Traefik Production Settings
TRAEFIK_LOG_LEVEL=WARN
TRAEFIK_DASHBOARD_ENABLED=true
TRAEFIK_DASHBOARD_INSECURE=false
TRAEFIK_TLS_ENABLED=true
TRAEFIK_ACME_EMAIL=admin@yourdomain.com

# Vault Production Settings
VAULT_LOG_LEVEL=WARN
VAULT_DEV_MODE=false
ENABLE_VAULT=true
```

### Generating Secure Keys

```bash
# Generate Consul encryption key
openssl rand -base64 32

# Generate secure tokens
openssl rand -hex 16
```

## Security Hardening

### 1. Enable TLS for All Services

#### Consul TLS

1. Generate TLS certificates:

```bash
# Create TLS directory
mkdir -p ./consul/config/certs

# Generate CA certificate
openssl req -new -x509 -days 365 -nodes \
  -out ./consul/config/certs/ca.pem \
  -keyout ./consul/config/certs/ca-key.pem

# Generate server certificate
openssl req -new -nodes \
  -out ./consul/config/certs/server.csr \
  -keyout ./consul/config/certs/server-key.pem
  
# Sign server certificate
openssl x509 -req -days 365 \
  -in ./consul/config/certs/server.csr \
  -CA ./consul/config/certs/ca.pem \
  -CAkey ./consul/config/certs/ca-key.pem \
  -CAcreateserial \
  -out ./consul/config/certs/server.pem
```

2. Update Consul environment variables:

```ini
CONSUL_TLS_ENABLED=true
CONSUL_CA_FILE=/consul/config/certs/ca.pem
CONSUL_CERT_FILE=/consul/config/certs/server.pem
CONSUL_KEY_FILE=/consul/config/certs/server-key.pem
```

#### Traefik TLS with Let's Encrypt

Enable automatic TLS certificate issuance:

```ini
TRAEFIK_TLS_ENABLED=true
TRAEFIK_ACME_EMAIL=admin@yourdomain.com
```

Update Traefik configuration in docker-compose.yml:

```yaml
services:
  traefik:
    # ...
    environment:
      # ...
      - TRAEFIK_ENTRYPOINTS_WEBSECURE_HTTP_TLS=true
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${TRAEFIK_ACME_EMAIL}
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/letsencrypt/acme.json
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_HTTPCHALLENGE=true
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_HTTPCHALLENGE_ENTRYPOINT=web
    volumes:
      # ...
      - letsencrypt:/letsencrypt

volumes:
  letsencrypt:
```

### 2. Secure Admin Interfaces

Secure the Traefik dashboard:

```yaml
labels:
  - "traefik.http.routers.traefik-dashboard.rule=Host(`traefik-dashboard.yourdomain.com`)"
  - "traefik.http.routers.traefik-dashboard.service=api@internal"
  - "traefik.http.routers.traefik-dashboard.middlewares=traefik-auth"
  - "traefik.http.middlewares.traefik-auth.basicauth.users=admin:$$apr1$$H6uskkkW$$IgXLP6ewTrSuBkTrqE8wj/"
  - "traefik.http.routers.traefik-dashboard.tls=true"
  - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt"
```

Generate basicauth credentials:

```bash
htpasswd -n admin
```

### 3. Network Security

Implement IP whitelisting for admin interfaces:

```yaml
labels:
  - "traefik.http.middlewares.admin-ipwhitelist.ipwhitelist.sourcerange=192.168.1.0/24,203.0.113.1/32"
  - "traefik.http.routers.traefik-dashboard.middlewares=admin-ipwhitelist"
```

### 4. Enable Consul ACLs

Enable ACLs in Consul:

```yaml
services:
  consul-server:
    environment:
      - CONSUL_ACL_ENABLED=true
      - CONSUL_ACL_DEFAULT_POLICY=deny
      - CONSUL_ACL_DOWN_POLICY=extend-cache
      - CONSUL_ACL_TOKENS_MASTER=<your-master-token>
```

Create policies and tokens for services:

```bash
# Create a policy
cat > service-policy.hcl << EOF
service "my-service" {
  policy = "write"
}
service_prefix "" {
  policy = "read"
}
EOF

# Create a token with that policy
consul acl policy create -name "my-service-policy" -rules @service-policy.hcl
consul acl token create -description "my-service token" -policy-name "my-service-policy"
```

### 5. Configure Vault for Production

Switch Vault to non-dev mode:

```ini
VAULT_DEV_MODE=false
```

Update Vault configuration:

```hcl
storage "consul" {
  address = "consul-server:8500"
  path = "vault/"
  token = "<consul-acl-token>"
  service_tags = "vault-server"
  redirect_addr = "https://vault.yourdomain.com"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_cert_file = "/vault/config/certs/vault.pem"
  tls_key_file = "/vault/config/certs/vault-key.pem"
}

ui = true
api_addr = "https://vault.yourdomain.com"
cluster_addr = "https://vault.node.yourdomain.com:8201"
```

Implement auto-unsealing (AWS KMS example):

```hcl
seal "awskms" {
  region     = "us-west-2"
  kms_key_id = "alias/vault-unseal-key"
}
```

## High Availability Configuration

### Consul Cluster

Create a multi-node Consul cluster:

```yaml
services:
  consul-server1:
    # ... 
    environment:
      - CONSUL_LOCAL_CONFIG={"server":true,"bootstrap_expect":3}
    
  consul-server2:
    # ...
    environment:
      - CONSUL_LOCAL_CONFIG={"server":true,"bootstrap_expect":3,"retry_join":["consul-server1"]}
    
  consul-server3:
    # ...
    environment:
      - CONSUL_LOCAL_CONFIG={"server":true,"bootstrap_expect":3,"retry_join":["consul-server1"]}
```

### Traefik Cluster

Run multiple Traefik instances:

```yaml
services:
  traefik1:
    # ...
  
  traefik2:
    # ...
```

Use a load balancer in front of the Traefik instances.

### Vault Backups

Set up regular Vault snapshots (if using integrated storage):

```bash
#!/bin/bash
# backup-vault.sh
DATE=$(date +%Y-%m-%d-%H-%M)
export VAULT_ADDR=https://vault.yourdomain.com
export VAULT_TOKEN=$(cat /path/to/secure/root-token.txt)

# Create snapshot
vault operator raft snapshot save ./backups/vault/vault-backup-$DATE.snap

# Encrypt the backup
gpg --encrypt --recipient admin@yourdomain.com ./backups/vault/vault-backup-$DATE.snap

# Remove unencrypted backup
rm ./backups/vault/vault-backup-$DATE.snap

# Clean up old backups (keep last 7 days)
find ./backups/vault/ -name "vault-backup-*.snap.gpg" -type f -mtime +7 -delete
```

Set up as a cron job:

```bash
0 3 * * * /path/to/backup-vault.sh >> /var/log/vault-backup.log 2>&1
```

### Docker Volume Backups

Back up persistent volumes:

```bash
#!/bin/bash
# backup-volumes.sh
DATE=$(date +%Y-%m-%d-%H-%M)
BACKUP_DIR="./backups/volumes/$DATE"

mkdir -p $BACKUP_DIR

# Stop the containers
docker-compose down

# Backup volumes
for VOLUME in $(docker volume ls -q | grep microservices); do
  docker run --rm -v $VOLUME:/source -v $BACKUP_DIR:/backup alpine \
    tar -czf /backup/$VOLUME.tar.gz -C /source .
done

# Restart the containers
docker-compose up -d

# Clean up old backups (keep last 7 days)
find ./backups/volumes/ -type d -mtime +7 -exec rm -rf {} \;
```

## Monitoring and Alerting

### Prometheus Monitoring

Add Prometheus for metrics collection:

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
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.yourdomain.com`)"
      - "traefik.http.routers.prometheus.middlewares=admin-ipwhitelist,admin-auth"
      - "traefik.http.routers.prometheus.tls=true"
      - "traefik.http.routers.prometheus.tls.certresolver=letsencrypt"

volumes:
  prometheus-data:
```

Prometheus configuration (`./prometheus/prometheus.yml`):

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'consul'
    consul_sd_configs:
      - server: 'consul-server:8500'
    relabel_configs:
      - source_labels: ['__meta_consul_service']
        target_label: 'service'
```

### Grafana Dashboards

Add Grafana for visualization:

```yaml
services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    volumes:
      - grafana-data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=<secure-password>
      - GF_USERS_ALLOW_SIGN_UP=false
    networks:
      - traefik-net
      - consul-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.yourdomain.com`)"
      - "traefik.http.routers.grafana.middlewares=admin-ipwhitelist"
      - "traefik.http.routers.grafana.tls=true"
      - "traefik.http.routers.grafana.tls.certresolver=letsencrypt"

volumes:
  grafana-data:
```

### AlertManager for Notifications

Add AlertManager for alerting:

```yaml
services:
  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager-data:/alertmanager
    command:
      - --config.file=/etc/alertmanager/alertmanager.yml
      - --storage.path=/alertmanager
    networks:
      - traefik-net
      - consul-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.alertmanager.rule=Host(`alerts.yourdomain.com`)"
      - "traefik.http.routers.alertmanager.middlewares=admin-ipwhitelist,admin-auth"
      - "traefik.http.routers.alertmanager.tls=true"
      - "traefik.http.routers.alertmanager.tls.certresolver=letsencrypt"

volumes:
  alertmanager-data:
```

AlertManager configuration (`./alertmanager/alertmanager.yml`):

```yaml
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp.yourdomain.com:587'
  smtp_from: 'alerts@yourdomain.com'
  smtp_auth_username: 'alerts@yourdomain.com'
  smtp_auth_password: '<smtp-password>'

route:
  group_by: ['alertname', 'job']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'email-team'

receivers:
- name: 'email-team'
  email_configs:
  - to: 'team@yourdomain.com'
    send_resolved: true
```

## Centralized Logging

### ELK Stack (Elasticsearch, Logstash, Kibana)

Add the ELK stack for centralized logging:

```yaml
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.14.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    volumes:
      - elasticsearch-data:/usr/share/elasticsearch/data
    networks:
      - traefik-net
      - consul-net
    deploy:
      resources:
        limits:
          memory: 1g

  logstash:
    image: docker.elastic.co/logstash/logstash:7.14.0
    container_name: logstash
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline
    environment:
      - XPACK_MONITORING_ENABLED=false
    depends_on:
      - elasticsearch
    networks:
      - traefik-net
      - consul-net

  kibana:
    image: docker.elastic.co/kibana/kibana:7.14.0
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch
    networks:
      - traefik-net
      - consul-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.kibana.rule=Host(`logs.yourdomain.com`)"
      - "traefik.http.routers.kibana.middlewares=admin-ipwhitelist,admin-auth"
      - "traefik.http.routers.kibana.tls=true"
      - "traefik.http.routers.kibana.tls.certresolver=letsencrypt"

volumes:
  elasticsearch-data:
```

### Filebeat for Log Collection

Add Filebeat to collect logs from services:

```yaml
services:
  filebeat:
    image: docker.elastic.co/beats/filebeat:7.14.0
    container_name: filebeat
    user: root
    volumes:
      - ./filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    depends_on:
      - elasticsearch
      - logstash
    networks:
      - consul-net
```

Filebeat configuration (`./filebeat/filebeat.yml`):

```yaml
filebeat.inputs:
- type: container
  enabled: true
  paths:
    - /var/lib/docker/containers/*/*.log

processors:
  - add_docker_metadata: ~
  - add_host_metadata: ~

output.logstash:
  hosts: ["logstash:5044"]
```

## Scaling and Load Balancing

### Horizontal Scaling

Scale services horizontally:

```yaml
services:
  my-service:
    deploy:
      mode: replicated
      replicas: 3
```

To scale manually:

```bash
docker-compose up -d --scale my-service=5
```

### Load Balancer Configuration

For cloud environments, configure a load balancer in front of Traefik:

AWS Example:
```
Load Balancer --> Traefik Instances --> Microservices
```

Ensure sticky sessions for path-based routing:

```
ALB Cookie Stickiness: AWSALB
Duration: 3600s
```

## Infrastructure as Code

For production, consider managing your infrastructure with tools like:

- Terraform for cloud resources
- Ansible for configuration management
- GitHub Actions or Jenkins for CI/CD pipelines

Example Terraform structure:
```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── modules/
│   ├── networking/
│   ├── compute/
│   ├── database/
│   └── dns/
└── environments/
    ├── staging/
    └── production/
```

## Deployment Pipeline

Create a CI/CD pipeline for automated deployments:

```yaml
# GitHub Actions Example (.github/workflows/deploy.yml)
name: Deploy to Production

on:
  push:
    branches:
      - main

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v2
        
      - name: Install SSH key
        uses: shimataro/ssh-key-action@v2
        with:
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          known_hosts: ${{ secrets.KNOWN_HOSTS }}
          
      - name: Deploy to production
        run: |
          ssh user@your-production-server.com "cd /path/to/deployment && git pull && docker-compose up -d --build"
```

## Disaster Recovery Plan

Create a detailed disaster recovery plan:

1. **Failover Procedures**:
   - Document steps to activate backup servers
   - Automate where possible

2. **Backup Verification**:
   - Regularly test backup restoration
   - Document verification procedures

3. **Recovery Time Objectives (RTO)**:
   - Define maximum acceptable downtime
   - Plan resources accordingly

4. **Recovery Point Objectives (RPO)**:
   - Define acceptable data loss
   - Adjust backup frequency accordingly

5. **Communication Plan**:
   - Define who to notify in case of outage
   - Establish a communication protocol

## Security Auditing

Implement regular security audits:

1. **Container Security Scanning**:
   ```bash
   docker scan myservice:latest
   ```

2. **Network Penetration Testing**:
   - Engage external security professionals
   - Test all exposed interfaces

3. **Secret Rotation**:
   - Implement automated secret rotation
   - Monitor for unauthorized access

4. **Compliance Checks**:
   - Verify against relevant standards (PCI-DSS, HIPAA, etc.)
   - Document compliance status

## Final Production Checklist

Before going live, verify:

- [ ] All services are running and healthy
- [ ] TLS certificates are valid and secure
- [ ] Backups are working and verified
- [ ] Monitoring is capturing all critical metrics
- [ ] Alerts are properly configured and tested
- [ ] Logging is capturing all required information
- [ ] All admin interfaces are securely accessible
- [ ] Load testing has been performed
- [ ] Security scans are clean
- [ ] Documentation is up-to-date
- [ ] Recovery procedures are documented and tested
- [ ] Team is trained on operations and maintenance

This checklist ensures your production deployment is robust, secure, and maintainable.
 HA

Run multiple Vault instances with Consul backend:

```yaml
services:
  vault1:
    # ...
    
  vault2:
    # ...
```

## Backup and Recovery Procedures

### Consul Backups

Set up regular Consul snapshots:

```bash
#!/bin/bash
# backup-consul.sh
DATE=$(date +%Y-%m-%d-%H-%M)
docker exec consul-server consul snapshot save /consul/data/backup-$DATE.snap
docker cp consul-server:/consul/data/backup-$DATE.snap ./backups/consul/
# Clean up old backups (keep last 7 days)
find ./backups/consul/ -name "backup-*.snap" -type f -mtime +7 -delete
```

Set up as a cron job:

```bash
0 2 * * * /path/to/backup-consul.sh >> /var/log/consul-backup.log 2>&1
```

### Vault