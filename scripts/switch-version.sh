#!/bin/bash
set -ebmuo pipefail

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    echo "Usage: $0 <version> <license>"
    exit 1
fi

LICENSE="${2:-}"
if [ -z "${LICENSE}" ]; then
    echo "Usage: $0 <version> <license>"
    exit 1
fi

sdb-admin -y delete-node --all
sdb-deploy -y uninstall --all-versions

/scripts/install.sh "${VERSION}"
/scripts/init.sh "${LICENSE}"
