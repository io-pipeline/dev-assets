# Gitea Actions Runners Deployment Guide

This guide explains how to deploy the Gitea Actions runners using the custom images we built.

## Runner Images

We maintain three runner images:

| Image | Size | Use Case |
|-------|------|----------|
| `git.rokkon.com/io-pipeline/gitea-runner:latest` | 1.53GB | Standard builds (default) |
| `git.rokkon.com/io-pipeline/gitea-runner:no-cuda` | 1.53GB | Same as latest |
| `git.rokkon.com/io-pipeline/gitea-runner:cuda13` | 9.1GB | GPU workloads with CUDA 13.0 |

All images include:
- Java 21 (Eclipse Temurin)
- Node.js 22 + pnpm
- Docker + Docker Compose + Docker Buildx
- Gradle init.gradle pre-configured with Nexus mirror

The CUDA image additionally includes:
- CUDA 13.0 toolkit + cuDNN
- Support for RTX 2070 (Turing) and RTX 4080 (Ada Lovelace) GPUs

## Runner Configuration

### Recommended Setup (3 runners)

- **Runner 1**: Non-CUDA, ubuntu-latest label
- **Runner 2**: Non-CUDA, ubuntu-latest label
- **Runner 3**: CUDA-enabled, ubuntu-latest + cuda labels with GPU access

### Docker Compose Example

```yaml
version: '3.8'

services:
  gitea-runner-1:
    image: gitea/act_runner:latest
    container_name: gitea-runner-1
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - gitea-runner-1-data:/data
    environment:
      - GITEA_INSTANCE_URL=https://git.rokkon.com
      - GITEA_RUNNER_REGISTRATION_TOKEN=${RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=pipeline-runner-1
      - GITEA_RUNNER_LABELS=ubuntu-latest:docker://git.rokkon.com/io-pipeline/gitea-runner:latest

  gitea-runner-2:
    image: gitea/act_runner:latest
    container_name: gitea-runner-2
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - gitea-runner-2-data:/data
    environment:
      - GITEA_INSTANCE_URL=https://git.rokkon.com
      - GITEA_RUNNER_REGISTRATION_TOKEN=${RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=pipeline-runner-2
      - GITEA_RUNNER_LABELS=ubuntu-latest:docker://git.rokkon.com/io-pipeline/gitea-runner:latest

  gitea-runner-3:
    image: gitea/act_runner:latest
    container_name: gitea-runner-3
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - gitea-runner-3-data:/data
    environment:
      - GITEA_INSTANCE_URL=https://git.rokkon.com
      - GITEA_RUNNER_REGISTRATION_TOKEN=${RUNNER_TOKEN}
      - GITEA_RUNNER_NAME=pipeline-runner-3-cuda
      # Supports both ubuntu-latest AND cuda workloads
      - GITEA_RUNNER_LABELS=ubuntu-latest:docker://git.rokkon.com/io-pipeline/gitea-runner:latest,cuda:docker://git.rokkon.com/io-pipeline/gitea-runner:cuda13
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

volumes:
  gitea-runner-1-data:
  gitea-runner-2-data:
  gitea-runner-3-data:
```

## Deployment Steps

### 1. Prerequisites on Runner Host

The runner host (krick-1) needs:

**For all runners:**
- Docker installed and running
- Access to `git.rokkon.com` registry
- Docker socket mounted (`/var/run/docker.sock`)

**For GPU runner (runner-3):**
- NVIDIA GPU (RTX 2070, RTX 4080, or compatible)
- NVIDIA Driver 580+ (with Open Kernel Modules recommended)
- nvidia-container-toolkit installed

Install nvidia-container-toolkit:
```bash
#!/bin/bash
# Add the repository
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Install
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Configure Docker
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 2. Deploy Runners

```bash
# Pull the latest images
docker pull git.rokkon.com/io-pipeline/gitea-runner:latest
docker pull git.rokkon.com/io-pipeline/gitea-runner:cuda13

# Deploy with docker-compose
docker-compose up -d

# Verify runners are up
docker ps | grep gitea-runner

# Check logs
docker logs gitea-runner-1
docker logs gitea-runner-2
docker logs gitea-runner-3
```

### 3. Verify Registration

Check your Gitea instance at `https://git.rokkon.com/org/settings/actions/runners` to see:
- ✅ pipeline-runner-1 (ubuntu-latest)
- ✅ pipeline-runner-2 (ubuntu-latest)
- ✅ pipeline-runner-3-cuda (ubuntu-latest, cuda)

## Using in Workflows

### Standard Build (Non-CUDA)

```yaml
name: Build and Test
on: [push]

jobs:
  build:
    runs-on: ubuntu-latest  # Uses runner 1 or 2
    steps:
      - uses: actions/checkout@v4
      - name: Build with Gradle
        run: ./gradlew build
```

### GPU Workload (CUDA)

```yaml
name: ML Training
on: [push]

jobs:
  train:
    runs-on: cuda  # Uses runner 3 with GPU
    steps:
      - uses: actions/checkout@v4
      - name: Train model
        run: python train.py
      - name: Verify GPU
        run: nvidia-smi
```

## Maintenance

### Updating Images

Rebuild and push updated images:
```bash
cd dev-assets/docker/gitea-runner

# Build
./build-no-cuda.sh  # For non-CUDA
./build.sh          # For CUDA

# Push
docker push git.rokkon.com/io-pipeline/gitea-runner:latest
docker push git.rokkon.com/io-pipeline/gitea-runner:cuda13

# Restart runners to pull new images
docker-compose restart
```

### Monitoring

Check runner status:
```bash
docker stats gitea-runner-1 gitea-runner-2 gitea-runner-3
```

View logs:
```bash
docker-compose logs -f
```

## Troubleshooting

### Runner Not Connecting

1. Check registration token is correct
2. Verify GITEA_INSTANCE_URL is accessible
3. Check Docker socket permissions
4. Review logs: `docker logs gitea-runner-X`

### GPU Not Available in Runner 3

1. Verify nvidia-container-toolkit: `nvidia-ctk --version`
2. Test GPU access: `docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi`
3. Check Docker daemon config: `cat /etc/docker/daemon.json`
4. Verify GPU devices: `ls /dev/nvidia*`

### Image Pull Failures

1. Login to registry: `docker login git.rokkon.com`
2. Verify network connectivity to registry
3. Check storage space: `df -h`
