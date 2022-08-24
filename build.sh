#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
    source .env
fi
if [[ -f config.env ]]; then
    source config.env
fi

if [ -z "${BOOTSTRAP_LICENSE-}" ]; then
    echo !!! ERROR !!!
    echo The BOOTSTRAP_LICENSE environment variable must be specified
    exit 1
fi

IMAGE_REPO=ghcr.io/singlestore-labs
IMAGE_NAME=singlestoredb-dev

docker build \
    -t "${IMAGE_REPO}/${IMAGE_NAME}:local" \
    --build-arg BOOTSTRAP_LICENSE=${BOOTSTRAP_LICENSE} \
    --build-arg RELEASE_CHANNEL=${RELEASE_CHANNEL} \
    --build-arg SERVER_VERSION=${SERVER_VERSION} \
    --build-arg CLIENT_VERSION=${CLIENT_VERSION} \
    --build-arg STUDIO_VERSION=${STUDIO_VERSION} \
    .
