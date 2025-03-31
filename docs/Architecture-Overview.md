# Architecture Overview

This document outlines the technical architecture for a robust, scalable microservice-based application. The architecture leverages modern technologies for containerization, service discovery, message queuing, secret management, service communication, monitoring, caching, object storage, high-performance database, API gateway, and service mesh capabilities.

## High-Level Architecture

The architecture follows modern microservices best practices with clear separation of concerns:

1. **Edge Layer**: Traefik serves as the API gateway, handling incoming requests, routing, and security
2. **Service Discovery**: Consul provides the foundation for service registration and discovery
3. **Secret Management**: HashiCorp Vault secures sensitive credentials and secrets
4. **Service Mesh**: Linkerd provides advanced service-to-service communication patterns
5. **Microservices**: Individual containerized services that perform specific business functions

## Request Flow

1. **Client Request**: A client makes an HTTP/HTTPS request to the system.
2. **Traefik Processing**:
   - The request hits Traefik, which acts as the API gateway and entry point.
   - Traefik has already loaded routing rules and middleware configurations from Consul.
   - Traefik applies configured middlewares (rate limiting, authentication, etc.) directly to the request.
3. **Request Forwarding**: After middleware processing, Traefik forwards the request to the appropriate microservice based on routing rules.
4. **Service Response**: The microservice processes the request and returns a response.
5. **Response Delivery**: Traefik forwards the response back to the client, potentially applying response middlewares.

## Service Registration Flow

1. **Service Startup**: When a microservice starts, it registers itself with Consul either:
   - Automatically via Docker labels (for containerized services)
   - Programmatically via Consul API (for services implementing direct registration)
2. **Health Checks**: Consul performs regular health checks to ensure the service is operational.
3. **Service Discovery**: Traefik and other services discover services through Consul's catalog or KV store.

## Service-to-Service Communication

1. **Service Discovery**: Microservice A queries Consul to discover the location of Microservice B.
2. **Direct Communication**: After discovery, Microservice A communicates directly with Microservice B.
3. **Communication Methods**:
   - REST/HTTP calls between services
   - gRPC for more efficient service-to-service communication
   - Event-based communication via message brokers (e.g., RabbitMQ)

Services do not communicate through Consul itself; they use Consul only to discover where other services are located. The actual communication happens directly between services.

## Configuration Flow

1. **Infrastructure Setup**: When the infrastructure starts, middleware configurations are registered in Consul KV store.
2. **Traefik Configuration**: 
   - Traefik loads initial configurations from Consul.
   - Traefik watches for changes to configurations in Consul and updates dynamically.
3. **Middleware Application**: 
   - Middlewares are configured in Consul and applied by Traefik during request processing.
   - Microservices reference these middlewares using labels or tags.
   - The actual middleware logic executes within Traefik, not as separate services.

## Secret Management Flow

1. **Vault Initialization**: On first startup, Vault is initialized and unsealed with encryption keys securely stored.
2. **Secret Loading**: Predefined secrets are loaded into Vault's key-value store.
3. **Service Authentication**: Microservices authenticate to Vault using the AppRole method.
4. **Secret Access**: 
   - Services request specific secrets they need from Vault.
   - Vault checks policies to ensure the service has appropriate access rights.
   - If approved, Vault provides the requested secrets to the service.
5. **Secret Rotation**: Credentials can be automatically rotated without service disruption.

## Architecture Diagram

A high-level architecture diagram should be created to illustrate the interaction between these components, showing:
- Container orchestration layer
- Traefik API gateway at the edge
- Linkerd service mesh for service-to-service communication
- Service discovery with Consul
- Message flow through RabbitMQ
- Redis caching layer
- ScyllaDB persistence layer
- MinIO object storage
- Secret management with Vault
- Monitoring with Prometheus

## Components Overview

The architecture leverages the following key technologies:

| Component | Technology | Purpose |
|-----------|------------|---------|
| Containerization | Docker | Application containerization |
| Orchestration | Docker Compose | Multi-container orchestration |
| Service Discovery | Consul | Service discovery and distributed configuration |
| API Gateway | Traefik | Edge router and API gateway |
| Service Mesh | Linkerd | Transparent service mesh |
| Message Queue | RabbitMQ | Asynchronous communication |
| Secret Management | HashiCorp Vault | Secure secret storage and management |
| Service Communication | gRPC | Efficient inter-service communication |
| Monitoring | Prometheus, Logstash, Jaeger | Metrics, logs, and tracing |
| Caching | Redis | In-memory data structure store |
| Object Storage | MinIO | S3-compatible object storage |
| Database | ScyllaDB | High-performance NoSQL database |

For detailed information about each component, see the Core Components page.