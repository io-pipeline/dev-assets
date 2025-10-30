# dev-assets

Development assets and resources for the io-pipeline platform.

## Purpose

This repository serves as a catch-all for development-related resources that don't belong in any specific production service repository. It contains tools, scripts, and documentation to support local development, testing, and learning about the io-pipeline ecosystem.

## What Goes Here

This repository is for non-production assets including:

- **Development Scripts** - Helper scripts for setting up local environments, running tests, managing services
- **Runtime Testing Tools** - Scripts and utilities for testing deployed services and infrastructure
- **Sample Docker Containers** - Example Docker configurations and compose files for local development
- **Dev Environment Setup** - Installation guides, configuration templates, and environment setup automation
- **Tutorials & Documentation** - Developer guides, architecture documentation, and getting-started tutorials
- **Sample Data & Fixtures** - Test data sets, mock APIs, and fixtures for development and testing
- **Prototypes & Experiments** - Proof-of-concept code and experimental features not ready for production

## What Doesn't Go Here

- Production code destined for deployment
- Service-specific implementation code (belongs in individual service repos)
- Sensitive credentials or secrets
- Large binary files or data sets (use appropriate storage solutions)

## Organization

Content will be organized into subdirectories as the repository grows:

```
/scripts          - Automation and helper scripts
/docker           - Docker and container configurations
/docs             - Documentation and tutorials
/samples          - Sample data and example code
/tools            - Development utilities and testing tools
```

## Getting Started

Check the `/docs` directory for setup guides and tutorials for getting started with io-pipeline development.

## Contributing

This is a living repository. Feel free to add helpful development resources, improve documentation, and share useful scripts that benefit the entire development team.
