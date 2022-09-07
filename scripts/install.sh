#!/bin/bash
set -ebmuo pipefail

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

sdb-deploy -y install \
    --force-package-format tar \
    --version "${VERSION}"
