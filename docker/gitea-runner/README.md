# Gitea Actions Runner with CUDA Support

Custom Docker image for Gitea Actions runners with GPU support for ML/AI workloads.

## Features

- **JDK 21** (Eclipse Temurin)
- **Node.js 22** + pnpm
- **Gradle** (pre-configured with Nexus mirror)
- **Docker** + Docker Compose (for Docker-in-Docker support)
- **CUDA 13.0** + cuDNN (Ubuntu 24.04)
- **GPU Support**: RTX 2070 (Turing), RTX 4080 (Ada Lovelace)

## Building

```bash
docker build -t git.rokkon.com/io-pipeline/gitea-runner:cuda13 .
```

## Running

The runner must have access to the Docker socket for DinD support:

```bash
docker run -d \
  --name gitea-runner \
  --gpus all \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /path/to/runner/config:/data \
  git.rokkon.com/io-pipeline/gitea-runner:cuda13
```

## Docker Compose Example

```yaml
version: '3.8'

services:
  gitea-runner:
    image: git.rokkon.com/io-pipeline/gitea-runner:cuda13
    container_name: gitea-runner
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./runner-config:/data
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    restart: unless-stopped
```

## Host Requirements

### NVIDIA Driver
- NVIDIA Open Kernel Modules (recommended) or proprietary driver
- Driver version 580+ (for CUDA 13.0 support)
- Both RTX 2070 and RTX 4080 supported

### Verify GPU Access
```bash
nvidia-smi
```

## Pre-configured Settings

### Gradle
- Nexus mirror: `https://maven.rokkon.com/repository/maven-public/`
- Configuration: `/root/.gradle/init.gradle`

### Environment
- `JAVA_HOME`: `/usr/lib/jvm/temurin-21-jdk-amd64`
- Working directory: `/workspace`
