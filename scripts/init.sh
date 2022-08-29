#!/bin/bash
set -euo pipefail

INIT_PW=$(date +%s | sha256sum | base64 | head -c 32)

MASTER_ID=$(
    memsqlctl -jy create-node \
        --no-start \
        --base-install-dir /data/master \
        --auditlogsdir /logs/master/auditlogs \
        --tracelogsdir /logs/master/tracelogs |
        jq .memsqlId -r
)

LEAF_ID=$(
    memsqlctl -jy create-node \
        --no-start \
        --base-install-dir /data/leaf \
        --auditlogsdir /logs/leaf/auditlogs \
        --tracelogsdir /logs/leaf/tracelogs \
        --port 3307 |
        jq .memsqlId -r
)

memsqlctl -y update-config --all --key minimum_core_count --value 0
memsqlctl -y update-config --all --key minimum_memory_mb --value 0
memsqlctl -y update-config --memsql-id ${MASTER_ID} --key http_proxy_port --value 9000

# this config is required for the cluster to upgrade since we aren't using toolbox
memsqlctl -y update-config --all --key unmanaged_cluster --value true

memsqlctl -y start-node --all

memsqlctl -y change-root-password --all --password "${INIT_PW}"

memsqlctl -y set-license --memsql-id ${MASTER_ID} --license "${BOOTSTRAP_LICENSE}"
memsqlctl -y bootstrap-aggregator --memsql-id ${MASTER_ID} --host 127.0.0.1
memsqlctl -y add-leaf --host 127.0.0.1 --port 3307 --password ${INIT_PW}

memsqlctl -y update-config --all --set-global --key enable_external_functions --value on
memsqlctl -y update-config --all --set-global --key http_api --value on

# stop the nodes to ensure we have a clean image state
memsqlctl -y stop-node --all

# take a backup of /data to support host volume initialization
rm /data/master/data/memsql.sock /data/master/data/memsql_proxy.sock
rm /data/leaf/data/memsql.sock /data/leaf/data/memsql_proxy.sock
tar -czf /startup/data.tgz -C /data .
