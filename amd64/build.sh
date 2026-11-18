#!/bin/sh

set -eu

DOCKER_USER="vbsdelnik"

IMAGE_NAME="amneziawg-client-amd64"
IMAGE_TAG="latest"

PLATFORM="linux/amd64"

DOCKERFILE="Dockerfile"

FULL_IMAGE="${DOCKER_USER}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "========================================"
echo "Building image:   ${FULL_IMAGE}"
echo "Platform:         ${PLATFORM}"
echo "Dockerfile:       ${DOCKERFILE}"
echo "========================================"

docker buildx build \
    -f "${DOCKERFILE}" \
    --pull \
    --no-cache \
    --progress plain \
    --platform "${PLATFORM}" \
    --tag "${FULL_IMAGE}" \
    --load \
    .

echo
echo "Build completed"
echo

docker image ls "${FULL_IMAGE}"

