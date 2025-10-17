#!/bin/bash
set -ebmuo pipefail

VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
    echo "Usage: $0 <version> <license>"
    exit 1
fi

LICENSE="BDBkMTllNTkxYmJlNDRlN2U5ZWYyM2YzZDRmN2YwY2FmAAAAAAAAAAAEAAAAAAAAACgwNQIZALfDACVybqBaHxUHdjHEfTPECqOfdquMVwIYUKDroCKPtLk0qAuwzFHh5L6GxwTw9vDzAA=="

sdb-admin -y delete-node --all
sdb-deploy -y uninstall --all-versions

/scripts/install.sh "${VERSION}"
/scripts/init.sh "${LICENSE}"
