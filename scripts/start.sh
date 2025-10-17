#!/bin/bash
set -ebmuo pipefail

# remove the .ready flag if it exists to make sure the healthcheck doesn't pass
# before everything has been initialized
rm -f /server/.ready

if [ -z "${SINGLESTORE_LICENSE-}" ]; then
    # We will use this free license from org 78758e03-2f10-431c-a819-fe8036dad3ef as a default license.
    SINGLESTORE_LICENSE="BDBkMTllNTkxYmJlNDRlN2U5ZWYyM2YzZDRmN2YwY2FmAAAAAAAAAAAEAAAAAAAAACgwNQIZALfDACVybqBaHxUHdjHEfTPECqOfdquMVwIYUKDroCKPtLk0qAuwzFHh5L6GxwTw9vDzAA=="
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
    if [[ "$CURRENT_VERSION" != "$SINGLESTORE_VERSION"* ]]; then
        echo "Switching SingleStore version from '${CURRENT_VERSION}' to '${SINGLESTORE_VERSION}'"
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

KAI_PROXY_PID=-1
ENABLE_KAI=${ENABLE_KAI:-0}
if [[ "${ENABLE_KAI,,}" == "1" || "${ENABLE_KAI,,}" == "true" ]]; then
    echo "Installing Kai Proxy..."
    DB=localhost:3306 PASSWORD=${ROOT_PASSWORD} ENABLE_TLS_TO_DB=0 ./kai/mongoproxy-install >/logs/kai.log
    DB=localhost:3306 ENABLE_TLS_TO_DB=0 ENABLE_TLS=false LISTEN_ON_HOST=0.0.0.0 LISTEN_ON_PORT=27017 UNSAFE_ALLOW_INSECURE_BINDING=1 ./kai/mongoproxy >>/logs/kai.log &
    KAI_PROXY_PID=$!
    LOG_FILES+=("/logs/kai.log")
fi
# tail the logs
tail --pid ${MASTER_PID} --pid ${LEAF_PID} -F $(printf '%s ' "${LOG_FILES[@]}") &
TAIL_PID=$!

cleanup() {
    set +mb # disable job control

    echo "Stopping Cluster..."
    memsqlctl -jy stop-node --all
    if [ ${KAI_PROXY_PID} -ne -1 ]; then
        kill ${KAI_PROXY_PID} 2>/dev/null || true
    fi
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
    # add kai proxy pid if it exists
    if [ ${KAI_PROXY_PID} -ne -1 ]; then
        PIDS+=(${KAI_PROXY_PID})
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
