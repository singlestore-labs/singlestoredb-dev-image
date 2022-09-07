#!/bin/bash
set -ebmuo pipefail

if [ -z "${SINGLESTORE_LICENSE-}" ]; then
    echo !!! ERROR !!!
    echo The SINGLESTORE_LICENSE environment variable must be specified when creating the Docker container
    exit 1
fi

if [ -z "${ROOT_PASSWORD-}" ]; then
    echo !!! ERROR !!!
    echo The ROOT_PASSWORD environment variable must be specified when creating the Docker container
    exit 1
fi

LOG_FILES=(
    "/logs/master/tracelogs/memsql.log"
    "/logs/leaf/tracelogs/memsql.log"
    "/var/lib/singlestoredb-studio/studio.log"
)

# initialize /data directory from /server/data.tgz if /data/nodes.hcl is missing
if [[ ! -f /data/nodes.hcl ]]; then
    tar -xzf /server/data.tgz -C /data
fi

# check to see if we need to switch versions at runtime
if [ -n "${SINGLESTORE_VERSION-}" ]; then
    CURRENT_VERSION=$(memsqlctl -j version | jq -r '"\(.version)-\(.commitHash[0:10])"')
    TARGET_VERSION="${SINGLESTORE_VERSION%%:*}"
    if [ "${CURRENT_VERSION}" != "${TARGET_VERSION}" ]; then
        echo "Switching SingleStore version from '${CURRENT_VERSION}' to '${TARGET_VERSION}'"
        /scripts/switch-version.sh "${SINGLESTORE_VERSION}" "${SINGLESTORE_LICENSE}"
    fi
fi

# start the nodes
echo "Starting SingleStore nodes..."
time memsqlctl -jy start-node --all

MASTER_ID=$(memsqlctl list-nodes --role master -q)
MASTER_PID=$(memsqlctl describe-node --memsql-id ${MASTER_ID} --property Pid)

LEAF_ID=$(memsqlctl list-nodes --role leaf -q)
LEAF_PID=$(memsqlctl describe-node --memsql-id ${LEAF_ID} --property Pid)

# update the pw
echo "Configuring SingleStore nodes..."
memsqlctl -jy change-root-password --all --password "${ROOT_PASSWORD}"

# set the correct license
memsqlctl -jy set-license --license "${SINGLESTORE_LICENSE}"

# run init.sql if it exists (and we haven't already run it)
if [[ -f /init.sql && ! -f /data/.init.sql.done ]]; then
    echo "Running init.sql..."
    singlestore -p${ROOT_PASSWORD} </init.sql
    touch /data/.init.sql.done
fi

# start studio last, this also allows studio to double purpose as a network accessible "ready" indicator
# which is useful for CI/CD environments which don't respect the Docker HEALTHCHECK
singlestoredb-studio --port 8080 1>/dev/null 2>/dev/null &
STUDIO_PID=$!

touch /server/.ready

# tail the logs
tail --pid ${MASTER_PID} --pid ${LEAF_PID} -F $(printf '%s ' "${LOG_FILES[@]}") &
TAIL_PID=$!

cleanup() {
    set +mb # disable job control

    echo "Stopping Cluster..."
    memsqlctl -jy stop-node --all
    kill ${STUDIO_PID} 2>/dev/null || true
    kill ${TAIL_PID} 2>/dev/null || true
    echo "Stopped."
}
trap cleanup SIGTERM SIGQUIT SIGINT

handle_sigchld() {
    # if any of our primary processes have died, clean up and exit
    for pid in ${MASTER_PID} ${LEAF_PID} ${STUDIO_PID}; do
        if ! kill -0 ${pid} &>/dev/null; then
            echo "Process ${pid} exited unexpectedly"
            cleanup
            exit 1
        fi
    done
}
trap handle_sigchld SIGCHLD

wait ${TAIL_PID} || true
exit 0
