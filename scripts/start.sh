#!/bin/bash
set -ebmuo pipefail

# remove the .ready flag if it exists to make sure the healthcheck doesn't pass
# before everything has been initialized
rm -f /server/.ready

if [ -z "${SINGLESTORE_LICENSE-}" ]; then
    echo "!!! ERROR !!!"
    echo "The SINGLESTORE_LICENSE environment variable must be specified when creating the Docker container"
    exit 1
fi

if [ -z "${ROOT_PASSWORD-}" ]; then
    echo "!!! ERROR !!!"
    echo "The ROOT_PASSWORD environment variable must be specified when creating the Docker container"
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

# set the correct license
# this must go first, otherwise we may run into a license error if subsequent queries codegen
memsqlctl -jy set-license --license "${SINGLESTORE_LICENSE}"

# set the correct root password
memsqlctl -jy change-root-password --all --password "${ROOT_PASSWORD}"

# set any dynamic globals from the environment
for var in "${!SINGLESTORE_SET_GLOBAL_@}"; do
    # read the value
    declare -n val="${var}"

    # remove prefix and make var lowercase
    var="${var#SINGLESTORE_SET_GLOBAL_}"
    var="${var,,}"

    echo "Setting ${var} to ${val}"
    sdb-admin -jy update-config --set-global --all \
        --key "${var}" --value "${val}"
done

INIT_SQL="${INIT_SQL:-/init.sql}"

# run init.sql if it exists (and we haven't already run it)
if [[ -f "${INIT_SQL}" && ! -f /data/.init.sql.done ]]; then
    echo "Running init.sql..."
    singlestore -p${ROOT_PASSWORD} < "${INIT_SQL}"
    touch /data/.init.sql.done
fi

# start studio last, this also allows studio to double purpose as a network accessible "ready" indicator
# which is useful for CI/CD environments which don't respect the Docker HEALTHCHECK
singlestoredb-studio --port 8080 1>/dev/null 2>/dev/null &
STUDIO_PID=$!

# check to see if we have an extension to run, and if so download + run it
EXTENSION_SCRIPT_PID=-1
if [ -n "${EXTENSION_URL-}" ]; then
    # for now we just support a single extension, but that might change
    # also we put the extension data dir in our persistent data dir which allows
    # extensions to persist between restarts
    EXTENSION_DATA_DIR="/data/extension/0"
    mkdir -p "${EXTENSION_DATA_DIR}"
    wget --no-check-certificate "${EXTENSION_URL}" -O "${EXTENSION_DATA_DIR}/extension.sh"
    chmod +x "${EXTENSION_DATA_DIR}/extension.sh"

    # run the extension in the background
    "${EXTENSION_DATA_DIR}/extension.sh" "${EXTENSION_DATA_DIR}" 2>&1 >/logs/extension.log &
    EXTENSION_SCRIPT_PID=$!

    # add log file to list of files to tail
    LOG_FILES+=("/logs/extension.log")
fi

# tail the logs
tail --pid ${MASTER_PID} --pid ${LEAF_PID} -F $(printf '%s ' "${LOG_FILES[@]}") &
TAIL_PID=$!

cleanup() {
    set +mb # disable job control

    echo "Stopping Cluster..."
    memsqlctl -jy stop-node --all
    kill ${EXTENSION_SCRIPT_PID} 2>/dev/null || true
    kill ${STUDIO_PID} 2>/dev/null || true
    kill ${TAIL_PID} 2>/dev/null || true
    echo "Stopped."
}
trap cleanup SIGTERM SIGQUIT SIGINT

handle_sigchld() {
    PIDS=(
        ${MASTER_PID}
        ${LEAF_PID}
        ${STUDIO_PID}
    )
    # add extension pid if it exists
    if [ ${EXTENSION_SCRIPT_PID} -ne -1 ]; then
        PIDS+=(${EXTENSION_SCRIPT_PID})
    fi

    # if any of our primary processes have died, clean up and exit
    for pid in "${PIDS[@]}"; do
        if ! kill -0 ${pid} &>/dev/null; then
            echo "Process ${pid} exited unexpectedly"
            cleanup
            exit 1
        fi
    done
}
trap handle_sigchld SIGCHLD

touch /server/.ready

wait ${TAIL_PID} || true
exit 0
