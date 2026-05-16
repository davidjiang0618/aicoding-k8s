#!/bin/bash

# Build the cc-dev Docker image for Claude Code isolated execution environment
# Usage:
#   ./build.sh          Build with Docker layer cache (fast)
#   ./build.sh clean    Build without cache (use when cache causes issues)
#
# Override image name and tag via environment variables:
#   IMAGE_NAME=cc-dev IMAGE_TAG=1.0.1 ./build.sh

cd "$(dirname "$0")"

IMAGE_NAME=${IMAGE_NAME:-cc-dev}
IMAGE_TAG=${IMAGE_TAG:-1.0.1}
USER_ID=${USER_ID:-$(id -u)}
GROUP_ID=${GROUP_ID:-$(id -g)}

BUILD_ARGS="--build-arg USER_ID=$USER_ID --build-arg GROUP_ID=$GROUP_ID"

if [ "$1" = "clean" ]; then
  docker build --no-cache $BUILD_ARGS -t ${IMAGE_NAME}:${IMAGE_TAG} .
else
  docker build $BUILD_ARGS -t ${IMAGE_NAME}:${IMAGE_TAG} .
fi
