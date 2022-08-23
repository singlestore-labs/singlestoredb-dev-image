#!/bin/bash
set -euo pipefail

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
    "/var/lib/memsql/master/tracelogs/memsql.log"
    "/var/lib/memsql/leaf/tracelogs/memsql.log"
    "/var/lib/singlestoredb-studio/studio.log"
)

# start the nodes
echo "Starting SingleStore nodes..."
time memsqlctl -jy start-node --all

# update the pw
echo "Configuring SingleStore nodes..."
memsqlctl -jy change-root-password --all --password "${ROOT_PASSWORD}"

# set the correct license
memsqlctl -jy set-license --license "${SINGLESTORE_LICENSE}"

# start studio
singlestoredb-studio --port 8080 1>/dev/null 2>/dev/null &
STUDIO_PID=$!

# run init.sql if it exists (and we haven't already run it)
if [[ -f /init.sql && ! -f /data/.init.sql.done ]]; then
    echo "Running init.sql..."
    memsql -p${ROOT_PASSWORD} </init.sql
    touch /data/.init.sql.done
fi

touch /home/memsql/.ready

# tail the logs
tail -F $(printf '%s ' "${LOG_FILES[@]}") &
TAIL_PID=$!

cleanup() {
    echo "Stopping Cluster..."
    memsqlctl -jy stop-node --all
    kill -15 ${STUDIO_PID}
    kill -15 ${TAIL_PID}
    echo "Stopped."
}

trap cleanup SIGTERM SIGQUIT SIGINT
wait $TAIL_PID
