# Adding Services

This page explains how to add microservices to the architecture. There are two main approaches:

1. Adding a service to the root Docker Compose file (recommended for development)
2. Creating a separate Docker Compose file for your service (better for complex production scenarios)

## Option 1: Adding a Service to the Root Docker Compose File

This approach is recommended for development and simpler deployments.

### Using an Existing Docker Image

To add a service using an existing image:

1. Edit the root `docker-compose.yaml` file and add your service configuration:

```yaml
services:
  # Existing services (consul-server, traefik, etc.)
  
  # Add your new service
  my-service:
    image: your-image:tag  # Replace with your image
    container_name: my-service
    restart: unless-stopped
    environment:
      - SERVICE_NAME=my-service
      # Add other environment variables as needed
    networks:
      - traefik-net
      - consul-net
    depends_on:
      - consul-server
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)"
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"
      - "traefik.http.middlewares.my-strip-prefix.stripprefix.prefixes=/my-service"
      - "traefik.http.routers.my-service.middlewares=my-strip-prefix,rate-limit@consul,secure-headers@consul"
      - "traefik.docker.network=microservices_template_traefik-net"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

2. Start your service:

```bash
docker-compose up -d my-service
```

### Using a Custom Dockerfile

For more control, you can build your own service image:

1. Create a directory for your service with a Dockerfile:

```bash
mkdir -p services/app-service
```

2. Create a Dockerfile in that directory:

```Dockerfile
# Choose a base image appropriate for your application
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy dependency definitions
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Expose the port your application uses
EXPOSE 8080

# Define healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Command to run the application
CMD ["npm", "start"]
```

3. Add your service to the Docker Compose file with a build directive:

```yaml
services:
  # Existing services (consul-server, traefik, etc.)
  
  # Add your new service with a Dockerfile
  app-service:
    build:
      context: ./services/app-service  # Path to your service directory
      dockerfile: Dockerfile           # Name of the Dockerfile
    container_name: app-service
    restart: unless-stopped
    environment:
      - SERVICE_NAME=app-service
      - NODE_ENV=development
      # Add other environment variables as needed
    volumes:
      - ./services/app-service:/app  # Mount source code for development
      - /app/node_modules            # Prevent overwriting node_modules
    networks:
      - traefik-net
      - consul-net
    depends_on:
      - consul-server
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app-service.rule=PathPrefix(`/app`)"
      - "traefik.http.services.app-service.loadbalancer.server.port=8080"
      - "traefik.http.middlewares.app-strip-prefix.stripprefix.prefixes=/app"
      - "traefik.http.routers.app-service.middlewares=app-strip-prefix,rate-limit@consul,secure-headers@consul"
      - "traefik.docker.network=microservices_template_traefik-net"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

4. Build and start your service:

```bash
# Build and start your service
docker-compose up -d --build app-service
```

### Example Language-Specific Dockerfiles

#### Node.js Service

```Dockerfile
FROM node:18-alpine

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

# Create a health check endpoint
RUN echo 'app.get("/health", (req, res) => res.status(200).send("OK"));' >> src/server.js

CMD ["node", "src/server.js"]
```

#### Python Service

```Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
```

#### Java Spring Boot Service

```Dockerfile
FROM maven:3.8.6-openjdk-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

FROM openjdk:17-slim
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

#### Go Service

```Dockerfile
FROM golang:1.21-alpine AS build

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o service ./cmd/server

FROM alpine:3.18
WORKDIR /app
COPY --from=build /app/service .
EXPOSE 8080
CMD ["./service"]
```

## Option 2: Using a Separate Docker Compose File

For more complex scenarios or when you want to keep services isolated, you can use a separate Docker Compose file.

1. Create a service directory:

```bash
mkdir -p services/my-service
cd services/my-service
```

2. Create a Docker Compose file (`docker-compose.yml`):

```yaml
services:
  my-service:
    image: your-image:tag
    container_name: my-service
    restart: unless-stopped
    networks:
      - traefik-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-service.rule=PathPrefix(`/my-service`)"
      - "traefik.http.services.my-service.loadbalancer.server.port=8080"
      - "traefik.http.routers.my-service.middlewares=rate-limit@consul,secure-headers@consul"
      - "traefik.docker.network=microservices_template_traefik-net"

networks:
  traefik-net:
    external: true
    name: microservices_template_traefik-net
```

3. Start your service:

```bash
docker-compose up -d
```

## Verifying Service Registration

After adding your service, verify that it's properly registered:

1. Check Consul for service registration:
   ```bash
   curl http://localhost:8500/v1/catalog/service/my-service
   ```
   
   Or visit the Consul UI at http://localhost:8500

2. Test that Traefik is properly routing to your service:
   ```bash
   curl http://localhost/my-service/
   ```

## Service Lifecycle Management

### With Root Docker Compose

When your service is part of the root Docker Compose file:

- **Starting all services**: `docker-compose up -d`
- **Stopping all services**: `docker-compose down`
- **View logs for a specific service**: `docker-compose logs my-service`
- **Restart a specific service**: `docker-compose restart my-service`

### With Separate Docker Compose File

When using a separate Docker Compose file:

- **Starting the service**: `cd services/my-service && docker-compose up -d`
- **Stopping the service**: `cd services/my-service && docker-compose down`
- **View logs**: `cd services/my-service && docker-compose logs`

## Service Configuration Management

For service-specific configurations:

1. Create a config directory for your service:

```bash
mkdir -p ./services/my-service/config
```

2. Add configuration files that will be mounted to the container:

```bash
# Example config file
cat > ./services/my-service/config/app-config.json << EOF
{
  "logLevel": "info",
  "timeout": 30,
  "features": {
    "caching": true,
    "metrics": true
  }
}
EOF
```

3. Update your service definition to mount this configuration:

```yaml
my-service:
  # ... other settings
  volumes:
    - ./services/my-service/config:/app/config
```

## Next Steps

After adding your services:

1. Learn how to [register services programmatically](Service-Registration)
2. Configure advanced [service routing](Service-Routing) with Traefik
3. Set up [secret management](Secret-Management) for your services