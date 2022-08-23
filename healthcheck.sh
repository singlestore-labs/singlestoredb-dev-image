#!/bin/bash
set -euo pipefail

if [[ ! -f /home/memsql/.ready ]]; then
    echo "The start script has not completed yet"
    exit 1
fi

MASTER_ID=$(memsqlctl list-nodes -q --role master)
memsqlctl query --sql "select 1" --memsql-id ${MASTER_ID}
