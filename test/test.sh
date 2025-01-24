#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

DEBUG_TESTS=${DEBUG_TESTS-}
if [[ -n "${DEBUG_TESTS}" ]]; then
    set -x
fi

if [[ -z "${SINGLESTORE_LICENSE}" ]]; then
    echo "The SINGLESTORE_LICENSE environment variable must be specified"
    exit 1
fi

IMAGE="${1-}"
if [[ -z "${IMAGE}" ]]; then
    echo "Usage: ./test.sh <image> [<test filter>]"
    exit 1
fi

TEST_FILTER="${2-}"

wait_for_healthy() {
    local container="${1}"
    local timeout="${2}"
    local logs_ts=$(date -uIseconds)

    echo "Waiting for container '${container}' to be healthy..."
    for i in $(seq ${timeout}); do
        local status=$(docker inspect -f '{{ .State.Status }}' ${container})
        if [[ "${status}" == "exited" ]]; then
            local exit_code=$(docker inspect -f '{{ .State.ExitCode }}' ${container})
            echo "Container exited with exit code ${exit_code}"
            docker logs ${container}
            exit 1
        fi

        local health_status=$(docker inspect -f '{{ .State.Health.Status }}' ${container})
        if [[ "${health_status}" == "healthy" ]]; then
            echo "Container is healthy."
            return 0
        fi
        if [[ $(expr ${i} % 5) == 0 ]]; then
            docker logs --since ${logs_ts} ${container}
            logs_ts=$(date -uIseconds)
        fi
        sleep 1
    done

    health_status=$(docker inspect -f '{{ .State.Health.Status }}' ${container})
    echo "Timeout exceeded; health_status: ${health_status}"
    exit 1
}

CURRENT_CONTAINER_ID=
VOLUME_ID=
TEMP_DIR=

docker_run() {
    CURRENT_CONTAINER_ID=$(
        docker run -d \
            -e SINGLESTORE_LICENSE=${SINGLESTORE_LICENSE} \
            -e ROOT_PASSWORD=test \
            "${@}" \
            ${IMAGE}
    )

    wait_for_healthy ${CURRENT_CONTAINER_ID} 90
    wait_for_all_dbs_online 30
}

docker_run_kai() {
    CURRENT_CONTAINER_ID=$(
        docker run -d \
            -e SINGLESTORE_LICENSE=${SINGLESTORE_LICENSE} \
            -e ROOT_PASSWORD=test \
            -e ENABLE_KAI=1 \
            "${@}" \
            ${IMAGE}
    )

    wait_for_healthy ${CURRENT_CONTAINER_ID} 90
    wait_for_all_dbs_online 30
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

wait_for_all_dbs_online() {
    local timeout="${1}"

    echo "Waiting for all databases to be online..."
    for i in $(seq ${timeout}); do
        local status=$(query_master "select bit_and(summary='healthy') as status from (select summary from information_schema.MV_DISTRIBUTED_DATABASES_STATUS union all select 'healthy' as summary)" | jq -r '.rows[0].status')
        if [[ "${status}" == "1" ]]; then
            echo "All databases are online."
            return 0
        fi
        sleep 1
    done

    echo "Timeout exceeded; status: ${status}"
    return 1
}

cleanup_container() {
    if [[ -n "${CURRENT_CONTAINER_ID}" && -z "${DEBUG_TESTS}" ]]; then
        echo "cleaning up container: ${CURRENT_CONTAINER_ID}"
        docker rm -v -f ${CURRENT_CONTAINER_ID} || true
    fi
}

cleanup_volume() {
    if [[ -n "${VOLUME_ID}" ]]; then
        echo "cleaning up volume: ${VOLUME_ID}"
        docker volume rm -f ${VOLUME_ID} || true
    fi
}

cleanup_tempdir() {
    if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
        echo "cleaning up tempdir: ${TEMP_DIR}"
        rm -r "${TEMP_DIR}" || true
    fi
}

cleanup() {
    echo "--------------------------------------------------------------------------------"
    echo "Cleaning up test containers, volumes, and directories"
    cleanup_container
    cleanup_volume
    cleanup_tempdir
    echo "Cleanup complete"
    echo "--------------------------------------------------------------------------------"
}

handle_exit() {
    exit_code=$?
    if [[ ${exit_code} != 0 ]]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "Tests FAILED"
        echo
        echo "Last container logs:"
        echo "------------------------------------------------------"
        docker logs ${CURRENT_CONTAINER_ID}
        echo "------------------------------------------------------"
        echo
    fi
    cleanup
}

trap cleanup SIGTERM SIGQUIT SIGINT
trap handle_exit EXIT

TESTS=()

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

    # verify that the singlestore UID is 999 and the singlestore GID is 998
    echo "verifying singlestore UID and GID are correct"
    local singlestore_uid=$(docker_exec id -u singlestore)
    local singlestore_gid=$(docker_exec id -g singlestore)
    if [[ ${singlestore_uid} != 999 || ${singlestore_gid} != 998 ]]; then
        echo "singlestore UID is ${singlestore_uid}, expected 999"
        echo "singlestore GID is ${singlestore_gid}, expected 998"
        exit 1
    fi

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
    wait_for_all_dbs_online 30

    COUNT_AFTER_RESTART=$(query_master "select count(*) from test.foo")

    if [[ "${COUNT}" != "${COUNT_AFTER_RESTART}" ]]; then
        echo "Count differs after restart"
        echo ${COUNT}
        echo ${COUNT_AFTER_RESTART}
        exit 1
    fi
}
TESTS+=("test_sanity")

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
TESTS+=("test_volumes")

# shared by test_init_sql_default and test_init_sql_env
init_sql_base_test() {
    COUNT=$(query_master "select count(*) as c from foo.bar" | jq -r '.rows[0].c')
    if [[ "${COUNT}" != "32" ]]; then
        echo "Count differs from what init.sql should have created"
        echo ${COUNT}
        exit 1
    fi

    # verify init.sql only runs once
    docker restart ${CURRENT_CONTAINER_ID}
    wait_for_healthy ${CURRENT_CONTAINER_ID} 30
    wait_for_all_dbs_online 30

    COUNT_AFTER_RESTART=$(query_master "select count(*) as c from foo.bar" | jq -r '.rows[0].c')
    if [[ "${COUNT_AFTER_RESTART}" != "32" ]]; then
        echo "Count differs from what test_init.sql should have created"
        echo ${COUNT_AFTER_RESTART}
        exit 1
    fi
}

# verify that init.sql works
test_init_sql_default() {
    docker_run -v "${SCRIPT_DIR}/init.sql:/init.sql"
    init_sql_base_test
}
TESTS+=("test_init_sql_default")

# verify that init.sql can be put in a different location
test_init_sql_env() {
    docker_run -v "${SCRIPT_DIR}/init.sql:/foo/bar.sql" -e INIT_SQL=/foo/bar.sql
    init_sql_base_test
}
TESTS+=("test_init_sql_env")

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
TESTS+=("test_http_api")

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
TESTS+=("test_external_functions")

test_fts() {
    docker_run

    query_master "create database fts"
    local auth=$(echo -n "root:test" | base64)
    query_master "create table fts.fts(t text, fulltext using version 2 (t))"
    query_master "insert into fts.fts values ('hello'), ('world')"
    query_master "optimize table fts.fts full"

    COUNT=$(query_master "select bm25(f, 't:hello') as h from fts.fts f" | jq -cr '.rows[]' | wc -l)
    if [ $COUNT -ne 2 ] ; then
        echo fts test failed: ${OUTPUT}
        exit 1
    fi
}
TESTS+=("test_fts")

test_auto_restart() {
    local exit_code

    # kill -9 on memsqld (i.e. a crash) should trigger auto-restart rather than crashing the container
    docker_run

    # get the master and leaf ids and d-pids (dpid is the pid of the memsqld process rather than memsqld_safe)
    MASTER_ID=$(docker exec ${CURRENT_CONTAINER_ID} memsqlctl list-nodes --role master -q)
    MASTER_PID=$(docker exec ${CURRENT_CONTAINER_ID} memsqlctl describe-node --memsql-id ${MASTER_ID} --property dpid)
    LEAF_ID=$(memsqlctl list-nodes --role leaf -q)
    LEAF_PID=$(docker exec ${CURRENT_CONTAINER_ID} memsqlctl describe-node --memsql-id ${LEAF_ID} --property dpid)

    # kill -9 the master and verify auto-restart
    docker exec ${CURRENT_CONTAINER_ID} kill -9 ${MASTER_PID}
    for i in $(seq 30); do
        exit_code=$(
            docker exec ${CURRENT_CONTAINER_ID} singlestore -ptest -e "select 1" >/dev/null 2>&1
            echo $?
        )
        if [[ ${exit_code} == 0 ]]; then
            break
        fi
        sleep 1
    done
    if [[ ${exit_code} != 0 ]]; then
        echo "Auto-restart failed"
        exit 1
    fi

    # kill -9 the leaf and verify auto-restart
    docker exec ${CURRENT_CONTAINER_ID} kill -9 ${LEAF_PID}
    for i in $(seq 30); do
        exit_code=$(
            docker exec ${CURRENT_CONTAINER_ID} singlestore -ptest --port 3307 -e "select 1" >/dev/null 2>&1
            echo $?
        )
        if [[ ${exit_code} == 0 ]]; then
            break
        fi
        sleep 1
    done
    if [[ ${exit_code} != 0 ]]; then
        echo "Auto-restart failed"
        exit 1
    fi
}
TESTS+=("test_auto_restart")

test_exit_status() {
    docker_run

    # should exit 0 for SIGINT, SIGTERM, SIGQUIT
    for sig in SIGINT SIGTERM SIGQUIT; do
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "container should exit 0 when receiving ${sig}"
        docker start ${CURRENT_CONTAINER_ID}
        wait_for_healthy ${CURRENT_CONTAINER_ID} 30

        echo "sending ${sig} to container ${CURRENT_CONTAINER_ID}"
        docker kill -s ${sig} ${CURRENT_CONTAINER_ID}
        echo "waiting for container to exit"
        local exit_code=$(docker wait ${CURRENT_CONTAINER_ID})
        if [[ ${exit_code} != "0" ]]; then
            echo "Exit code is ${exit_code} instead of 0"
            exit 1
        fi
    done

    # should have a non-zero exit code when sub-processes exit unexpectedly
    for role in master leaf; do
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "container should exit non-zero when ${role} exits unexpectedly"

        docker start ${CURRENT_CONTAINER_ID}
        wait_for_healthy ${CURRENT_CONTAINER_ID} 30

        docker exec ${CURRENT_CONTAINER_ID} memsqlctl stop-node -yj --role ${role}
        local exit_code=$(docker wait ${CURRENT_CONTAINER_ID})
        if [[ ${exit_code} == "0" ]]; then
            echo "Exit code is ${exit_code} instead of non-zero"
            exit 1
        fi
    done
}
TESTS+=("test_exit_status")

# this test should verify that we can safely upgrade from the latest version of this image
test_upgrade() {
    VOLUME_ID=$(docker volume create)

    # run the latest version of the image
    docker pull ghcr.io/singlestore-labs/singlestoredb-dev:latest || {
        echo "Skipping upgrade test - failed to pull latest image"
        return 0
    }

    CURRENT_CONTAINER_ID=$(
        docker run -d \
            -e SINGLESTORE_LICENSE=${SINGLESTORE_LICENSE} \
            -e ROOT_PASSWORD=test \
            -v ${VOLUME_ID}:/data \
            ghcr.io/singlestore-labs/singlestoredb-dev:latest
    )
    wait_for_healthy ${CURRENT_CONTAINER_ID} 30

    # create a database and table
    query_master "create database test"
    query_master "create table test.foo (id int)"
    query_master "insert into test.foo (id) values (1)"
    COUNT=$(query_master "select count(*) from test.foo")

    # stop and remove the container
    cleanup_container

    # run the current version of the image
    docker_run -v ${VOLUME_ID}:/data
    wait_for_healthy ${CURRENT_CONTAINER_ID} 30
    wait_for_all_dbs_online 30

    # verify that the database and table still exist
    COUNT_AFTER_RECREATE=$(query_master "select count(*) from test.foo")
    if [[ "${COUNT}" != "${COUNT_AFTER_RECREATE}" ]]; then
        echo "Count differs after recreate"
        echo ${COUNT}
        echo ${COUNT_AFTER_RECREATE}
        exit 1
    fi
}
TESTS+=("test_upgrade")

# this test should verify that we can switch the version at runtime
test_switch_version() {
    local target_version=7.8.13
    docker_run -e SINGLESTORE_VERSION=${target_version}

    local version=$(query_master "select @@memsql_version" | jq -r '.rows[0]."@@memsql_version"')
    if [[ "${version}" != "${target_version}" ]]; then
        echo "Version is ${version} instead of ${target_version}"
        exit 1
    fi
}
TESTS+=("test_switch_version")

test_set_global() {
    docker_run \
        -e SINGLESTORE_SET_GLOBAL_DEFAULT_PARTITIONS_PER_LEAF=2 \
        -e SINGLESTORE_SET_GLOBAL_cluster_NAME=foobar

    query_master "create database test"
    PARTITIONS=$(query_master "show partitions on test" | jq -r '.rows | length')
    if [[ "${PARTITIONS}" != "2" ]]; then
        echo "Partitions is ${PARTITIONS} instead of 2"
        exit 1
    fi

    CLUSTER_NAME=$(query_master "select @@cluster_name" | jq -r '.rows[0]."@@cluster_name"')
    if [[ "${CLUSTER_NAME}" != "foobar" ]]; then
        echo "Cluster name is ${CLUSTER_NAME} instead of foobar"
        exit 1
    fi
}
TESTS+=("test_set_global")

test_kai() {
    docker_run_kai
    # this is a binary handshake and list databases command, if we see the
    # information_schema database in the output then we know kai is working
    docker_exec echo \
    6d0000001a00000000000000dd0700000100000000540000001069734d6173746572000100000008 \
    6c6f616442616c616e6365640001036c736964001e0000000569640010000000049214bd5329704a \
    8fb613cacad4ee22f0000224646200050000007465737400004eb562dd8f0000001e000000000000 \
    00dd070000010000000076000000107361736c53746172740001000000026d656368616e69736d00 \
    06000000504c41494e00036f7074696f6e73001900000008736b6970456d70747945786368616e67 \
    65000100057061796c6f6164000e00000000726f6f7400726f6f7400746573740224646200060000 \
    0061646d696e0000857e41c3670000000400000000000000dd07000001000000004e000000016c69 \
    737444617461626173657300000000000000f03f036c736964001e0000000569640010000000049a \
    37f23630764443a379823b4e08b22400022464620005000000746573740000b177fe52 | \
    xxd -r -p | nc -q 1 127.0.0.1 27017 | grep "information_schema"
    if [[ $? -ne 0 ]]; then
        echo "Kai test failed"
        exit 1
    fi
}
TESTS+=("test_kai")

run_test() {
    echo "Running ${1}..."
    ${1}
    echo "Test ${1}: PASSED"

    cleanup
}

# count number of test_ functions and ensure it matches the number of tests in $TESTS
DEFINED_TESTS=$(declare -F | grep 'declare -f test_' | wc -l)
if [[ ${DEFINED_TESTS} != ${#TESTS[@]} ]]; then
    echo "Number of tests defined (${DEFINED_TESTS}) does not match number of tests in TESTS (${#TESTS[@]})"
    exit 1
fi

# only run tests which match $TEST_FILTER if TEST_FILTER is set
if [[ -n "${TEST_FILTER}" ]]; then
    # if no tests match filter then exit with an error
    if [[ $(echo "${TESTS[@]}" | grep -c "${TEST_FILTER}") == "0" ]]; then
        echo "No tests match filter ${TEST_FILTER}"
        exit 1
    fi

    echo "Running tests matching ${TEST_FILTER}"
    for test in "${TESTS[@]}"; do
        if [[ "${test}" =~ ${TEST_FILTER} ]]; then
            run_test ${test}
        fi
    done
else
    echo "Running all tests"
    for test in "${TESTS[@]}"; do
        run_test ${test}
    done
fi

echo "!!!!!!!!!!!!!!!!!!!!!!"
echo "!! All tests passed !!"
echo "!!!!!!!!!!!!!!!!!!!!!!"
