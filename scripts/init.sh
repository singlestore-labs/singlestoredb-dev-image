#!/bin/bash
set -euo pipefail

LICENSE="${1:-}"
if [ -z "${LICENSE}" ]; then
    echo "Usage: $0 <bootstrap license key>"
    exit 1
fi

INIT_PW=$(date +%s | sha256sum | base64 | head -c 32)

MASTER_ID=$(
    sdb-admin -jy create-node \
        --no-start \
        --base-install-dir /data/master \
        --auditlogsdir /logs/master/auditlogs \
        --tracelogsdir /logs/master/tracelogs |
        jq .memsqlId -r
)

LEAF_ID=$(
    sdb-admin -jy create-node \
        --no-start \
        --base-install-dir /data/leaf \
        --auditlogsdir /logs/leaf/auditlogs \
        --tracelogsdir /logs/leaf/tracelogs \
        --port 3307 |
        jq .memsqlId -r
)

sdb-admin -y update-config --all --key minimum_core_count --value 0
sdb-admin -y update-config --all --key minimum_memory_mb --value 0
sdb-admin -y update-config --memsql-id ${MASTER_ID} --key http_proxy_port --value 9000

# this config is required for the cluster to upgrade since we aren't using toolbox
sdb-admin -y update-config --all --key unmanaged_cluster --value true

sdb-admin -y start-node --all

sdb-admin -y change-root-password --all --password "${INIT_PW}"

sdb-admin -y bootstrap-aggregator --memsql-id ${MASTER_ID} --license "${LICENSE}"
sdb-admin -y add-leaf --host 127.0.0.1 --port 3307 --password ${INIT_PW}

sdb-admin -y update-config --all --set-global --key enable_external_functions --value on
sdb-admin -y update-config --all --set-global --key http_api --value on
sdb-admin -y update-config --all --set-global --key fts2_java_path --value /usr/local/jdk-21/bin/java
sdb-admin -y update-config --all --set-global --key fts2_java_home --value /usr/local/jdk-21
sdb-admin -y update-config --all --set-global --key java_pipelines_java_path --value /usr/local/jdk-21/bin/java
sdb-admin -y update-config --all --set-global --key java_pipelines_java11_path --value /usr/local/jdk-21/bin/java

isEngineVersionGE()
{
    local arg_major=${1}
    local arg_minor=${2}

    local version=$(memsqlctl version | sed -n 's/^Version: \(.*\)$/\1/p')
    local versionParts=($(echo ${version//./ }))
    local major=${versionParts[0]}
    local minor=${versionParts[1]}
    local patch=${versionParts[2]}

    if [[ "${major}" -ne ${arg_major} ]]; then
        if [[ "${major}" -gt ${arg_major} ]]; then
            return 0
        else
            return 1
        fi
    fi

    if [[ "${minor}" -ne ${arg_minor} ]]; then
        if [[ "${minor}" -gt ${arg_minor} ]]; then
            return 0
        else
            return 1
        fi
    fi

    return 0
}

if isEngineVersionGE 8 5; then
    sdb-admin -y update-config --all --set-global --key java_pipelines_java11_path --value /usr/bin/java
fi

# stop the nodes to ensure we have a clean image state
sdb-admin -y stop-node --all

# take a backup of /data to support host volume initialization
rm /data/master/data/memsql.sock /data/master/data/memsql_proxy.sock
rm /data/leaf/data/memsql.sock /data/leaf/data/memsql_proxy.sock
tar -czf /server/data.tgz -C /data .
