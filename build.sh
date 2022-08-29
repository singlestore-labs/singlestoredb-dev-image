#!/usr/bin/env bash
set -euo pipefail

CHANNEL="${1:-cloud}"

# error if CHANNEL is not cloud or onprem
if [[ "$CHANNEL" != "cloud" && "$CHANNEL" != "onprem" ]]; then
    echo "Invalid channel: $CHANNEL; must be cloud or onprem"
    exit 1
fi

if [[ -f .env ]]; then
    source .env
fi

if [ -z "${BOOTSTRAP_LICENSE-}" ]; then
    echo "!!! ERROR !!!"
    echo "The BOOTSTRAP_LICENSE environment variable must be specified"
    exit 1
fi

IMAGE_REPO=ghcr.io/singlestore-labs
IMAGE_NAME=singlestoredb-dev

docker build \
    -t "${IMAGE_REPO}/${IMAGE_NAME}:${CHANNEL}-local" \
    --build-arg BOOTSTRAP_LICENSE=${BOOTSTRAP_LICENSE} \
    --build-arg CONFIG="$(jq .${CHANNEL} config.json)" \
    .
