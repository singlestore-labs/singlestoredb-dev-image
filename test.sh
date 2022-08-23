#!/usr/bin/env bash
set -euo pipefail

DEBUG_TESTS=${DEBUG_TESTS-}
if [[ -n "${DEBUG_TESTS}" ]]; then
    set -x
fi

if [[ -z "${SINGLESTORE_LICENSE}" ]]; then
    echo "The SINGLESTORE_LICENSE environment variable must be specified"
    exit 1
fi

IMAGE="${1}"
if [[ -z "${IMAGE}" ]]; then
    echo "Usage: ./test.sh <image>"
    exit 1
fi

wait_for_healthy() {
    local container="${1}"
    local timeout="${2}"

    echo "Waiting for container '${container}' to be healthy..."
    for i in $(seq ${timeout}); do
        status=$(docker inspect -f '{{ .State.Health.Status }}' ${container})
        if [[ "${status}" == "healthy" ]]; then
            echo "Container is healthy."
            return 0
        fi
        if [[ $(expr ${i} % 5) == 0 ]]; then
            docker logs ${container}
        fi
        sleep 1
    done

    status=$(docker inspect -f '{{ .State.Health.Status }}' ${container})
    echo "Timeout exceeded; status: ${status}"
    return 1
}

CURRENT_CONTAINER_ID=
VOLUME_ID=

docker_run() {
    CURRENT_CONTAINER_ID=$(
        docker run -d \
            -e SINGLESTORE_LICENSE=${SINGLESTORE_LICENSE} \
            -e ROOT_PASSWORD=test \
            "${@}" \
            ${IMAGE}
    )

    wait_for_healthy ${CURRENT_CONTAINER_ID} 30
}

docker_exec() {
    if [[ -z "${CURRENT_CONTAINER_ID}" ]]; then
        echo "No container running"
        return 1
    fi

    docker exec ${CURRENT_CONTAINER_ID} "${@}"
}

memsqlctl() {
    docker_exec memsqlctl -y "${@}"
}

query_master() {
    MASTER_ID=$(memsqlctl list-nodes --role master -q)
    memsqlctl --json query --memsql-id ${MASTER_ID} -e "${1}"
}

cleanup_container() {
    if [[ -n "${CURRENT_CONTAINER_ID}" && -z "${DEBUG_TESTS}" ]]; then
        docker rm -f ${CURRENT_CONTAINER_ID} || true
    fi
}

cleanup_volume() {
    if [[ -n "${VOLUME_ID}" ]]; then
        docker volume rm ${VOLUME_ID} || true
    fi
}

cleanup() {
    echo "Cleaning up..."
    cleanup_container
    cleanup_volume
}

trap cleanup SIGTERM SIGQUIT SIGINT EXIT

test_sanity() {
    # start with a vanilla container to do some sanity checks
    docker_run

    echo "verifying process shows up in process table"
    [[ $(docker_exec ps aux | grep memsqld_safe | grep -v grep | wc -l) -eq 2 ]] || (
        docker_exec ps aux
        exit 1
    )

    echo "verifying studio is running"
    [[ $(docker_exec ps aux | grep singlestoredb-studio | grep -v grep | wc -l) -eq 2 ]] || (
        docker_exec ps aux
        exit 1
    )

    echo "verifying queries & creating test data"
    query_master "create database test"
    query_master "create table test.foo (id int)"
    query_master "insert into test.foo (id) values (1)"
    query_master "insert into test.foo (id) values (1)"
    query_master "insert into test.foo select * from test.foo"
    query_master "insert into test.foo select * from test.foo"
    query_master "insert into test.foo select * from test.foo"
    query_master "insert into test.foo select * from test.foo"

    COUNT=$(query_master "select count(*) from test.foo")

    docker restart ${CURRENT_CONTAINER_ID}
    wait_for_healthy ${CURRENT_CONTAINER_ID} 30

    COUNT_AFTER_RESTART=$(query_master "select count(*) from test.foo")

    if [[ "${COUNT}" != "${COUNT_AFTER_RESTART}" ]]; then
        echo "Count differs after restart"
        echo ${COUNT}
        echo ${COUNT_AFTER_RESTART}
        exit 1
    fi
}

# verify that volumes work
test_volumes() {
    VOLUME_ID=$(docker volume create)
    docker_run -v ${VOLUME_ID}:/data

    query_master "create database test"
    query_master "create table test.foo (id int)"
    query_master "insert into test.foo (id) values (1)"

    COUNT=$(query_master "select count(*) from test.foo")

    cleanup_container

    docker_run -v ${VOLUME_ID}:/data

    COUNT_AFTER_RECREATE=$(query_master "select count(*) from test.foo")

    if [[ "${COUNT}" != "${COUNT_AFTER_RECREATE}" ]]; then
        echo "Count differs after recreate"
        echo ${COUNT}
        echo ${COUNT_AFTER_RECREATE}
        exit 1
    fi
}

# verify that init.sql works
test_init_sql() {
    docker_run -v "${PWD}/test_init.sql:/init.sql"

    COUNT=$(query_master "select count(*) as c from foo.bar" | jq -r '.rows[0].c')
    if [[ "${COUNT}" != "32" ]]; then
        echo "Count differs from what test_init.sql should have created"
        echo ${COUNT}
        exit 1
    fi
}

test_http_api() {
    docker_run

    query_master "create database test"
    query_master "create table test.foo (id int)"
    query_master "insert into test.foo (id) values (1)"

    docker_exec curl -s localhost:9000/ping >/dev/null

    COUNT=$(docker_exec curl -s -H "content-type: application/json" -d '{"sql":"select count(*) as c from test.foo"}' root:test@localhost:9000/api/v2/query/rows | jq -r '.results[0].rows[0].c')
    if [[ "${COUNT}" != "1" ]]; then
        echo "Count differs from expected"
        echo ${COUNT}
        exit 1
    fi
}

test_external_functions() {
    docker_run

    query_master "create database test"
    local auth=$(echo -n "root:test" | base64)
    query_master "create link test.api as http credentials '{\"headers\": {\"Authorization\": \"Basic ${auth}\"}}'"
    query_master "create external function test.check_api() returns text as remote service 'localhost:9000/api/v1/query/tuples' format json link test.api"

    OUTPUT=$(query_master "select test.check_api()" 2>&1 || true)
    if [[ ${OUTPUT} != *Query\ was\ empty ]]; then
        echo "external functions failed: ${OUTPUT}"
        exit 1
    fi
}

run_test() {
    echo "Running test ${1}..."
    ${1}
    echo "Test ${1}: PASSED"

    cleanup
}

run_test test_sanity
run_test test_volumes
run_test test_init_sql
run_test test_http_api
run_test test_external_functions
