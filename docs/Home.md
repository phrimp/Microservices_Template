Welcome to the Microservices Architecture Template Wiki! This Wiki provides comprehensive documentation for setting up and using our robust, scalable microservice-based application infrastructure.

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- Git installed
- Basic understanding of containerization and microservices
- Free ports as specified in the `.env` file (by default: 80, 443, 8080, 8500, 8600, 8200)

### Setup Steps

1. Clone the repository
2. Configure environment variables in `.env`
3. Start the core infrastructure with `docker-compose up -d`
4. Access the management dashboards:
   - **Consul Dashboard**: http://localhost:8500
   - **Traefik Dashboard**: http://localhost:8080
   - **Vault Dashboard**: http://localhost:8200
5. Add your services (see [[Adding Services](../../wiki/Adding-Services)](Adding-Services))

## Wiki Content

This Wiki is organized into the following sections:

### Core Documentation

- [[Architecture Overview](../../wiki/Architecture-Overview)](Architecture-Overview) - Detailed explanation of the architecture design
- [[Core Components](../../wiki/Core-Components)](Core-Components) - Information about Consul, Traefik, and Vault
- [[Detailed Setup](../../wiki/Detailed-Setup)](Detailed-Setup) - Step-by-step setup instructions

### Working with Services

- [[Adding Services](../../wiki/Adding-Services)](Adding-Services) - How to add microservices to the architecture
- [[Service Registration](../../wiki/Service-Registration)](Service-Registration) - Methods for registering services with Consul
- [[Service Routing](../../wiki/Service-Routing)](Service-Routing) - Configuring Traefik for routing to services

### Advanced Topics

- [[Secret Management](../../wiki/Secret-Management)](Secret-Management) - Working with Vault for secrets
- [[Health Checks](../../wiki/Health-Checks)](Health-Checks) - Implementing and monitoring service health
- [[Advanced Features](../../wiki/Advanced-Features)](Advanced-Features) - Advanced capabilities of each component
- [[Production Deployment](../../wiki/Production-Deployment)](Production-Deployment) - Checklist and best practices for production

## License

This project is licensed under the MIT License - see the LICENSE file for details.