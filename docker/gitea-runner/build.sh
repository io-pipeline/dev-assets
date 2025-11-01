#!/bin/bash
set -e

IMAGE_NAME="git.rokkon.com/io-pipeline/gitea-runner"
TAG="cuda13"

echo "Building Gitea runner image with CUDA 13.0 support..."
docker build -t ${IMAGE_NAME}:${TAG} .

echo "Tagging as latest..."
docker tag ${IMAGE_NAME}:${TAG} ${IMAGE_NAME}:latest

echo "Build complete!"
echo "Image: ${IMAGE_NAME}:${TAG}"
echo ""
echo "To push to registry:"
echo "  docker push ${IMAGE_NAME}:${TAG}"
echo "  docker push ${IMAGE_NAME}:latest"
