#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <tag> <image-version> <singlestore-version>"
    echo "  tag: cloud or onprem"
    echo "  image-version: the new version of the image"
    echo "  singlestore-version: the new version of the server"
    exit 1
}

TAG="${1:-cloud}"
if [[ "$TAG" != "cloud" && "$TAG" != "onprem" ]]; then
    usage
fi

IMAGE_VERSION="${2:-}"
if [[ -z "$IMAGE_VERSION" ]]; then
    usage
fi

SINGLESTORE_VERSION="${3:-}"
if [[ -z "$SINGLESTORE_VERSION" ]]; then
    usage
fi

NEW_CONFIG=$(jq ".${TAG}.server=\"${SINGLESTORE_VERSION}\"" config.json)
echo ${NEW_CONFIG} | jq . >config.json

PREV_CHANGELOG=$(tail -n +2 CHANGELOG.md)

VERSION_NAME="SingleStoreDB Cloud Version"
if [[ "$TAG" == "onprem" ]]; then
    VERSION_NAME="SingleStoreDB On-Premises Version"
fi

cat >CHANGELOG.md <<EOF
# Changelog

## ${IMAGE_VERSION} - $(date "+%F")

 - ${VERSION_NAME} ${SINGLESTORE_VERSION}

${PREV_CHANGELOG}
EOF
