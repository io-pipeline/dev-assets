#!/bin/bash
set -e

IMAGE_NAME="git.rokkon.com/io-pipeline/gitea-runner"
TAG="latest"

echo "Building Gitea runner image WITHOUT CUDA (standard builds)..."
docker build -f Dockerfile.no-cuda -t ${IMAGE_NAME}:${TAG} .
docker tag ${IMAGE_NAME}:${TAG} ${IMAGE_NAME}:no-cuda

echo "Build complete!"
echo "Image: ${IMAGE_NAME}:${TAG}"
echo "Also tagged as: ${IMAGE_NAME}:no-cuda"
echo ""
echo "To push to registry:"
echo "  docker push ${IMAGE_NAME}:${TAG}"
echo "  docker push ${IMAGE_NAME}:no-cuda"
