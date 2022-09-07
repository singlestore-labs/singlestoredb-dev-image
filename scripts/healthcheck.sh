#!/bin/bash
set -euo pipefail

if [[ ! -f /server/.ready ]]; then
    echo "The start script has not completed yet"
    exit 1
fi

MASTER_ID=$(memsqlctl list-nodes -q --role master)
memsqlctl query --sql "select 1" --memsql-id ${MASTER_ID}

LEAF_ID=$(memsqlctl list-nodes -q --role leaf)
memsqlctl query --sql "select 1" --memsql-id ${LEAF_ID}
