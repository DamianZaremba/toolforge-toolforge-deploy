#!/usr/bin/env bats
# bats file_tags=admin,logging

set -o nounset

setup() {
    load "logging-common"
    _logging_setup
}

@test "alloy runs on every node" {
    node_count="$($SUKUBECTL get nodes --no-headers | wc -l)"

    run --separate-stderr retry "[[ \"\$($SUKUBECTL -n alloy get daemonset alloy -o jsonpath='{.status.numberReady}')\" == '$node_count' ]]" 60
    assert_success
}

@test "loki-infrastructure refuses requests without a tenant ID" {
    _start_loki_infrastructure_port_forward

    run --separate-stderr curl --silent --output /dev/null --write-out '%{http_code}' "$LOKI_INFRASTRUCTURE_URL/loki/api/v1/labels"
    assert_success
    assert_output "401"
}

@test "loki-infrastructure has logs of toolforge and upstream components" {
    _start_loki_infrastructure_port_forward
    namespaces_command="$(_loki_infrastructure_label_values_command namespace)"

    # Alloy can need some time to send the first logs after a deploy.
    run --separate-stderr retry "$namespaces_command | grep --line-regexp --quiet jobs-api" 60
    assert_success

    run --separate-stderr bash -c "$namespaces_command"
    assert_success
    assert_line "jobs-api"
    assert_line "kube-system"
    assert_line "istio-gateway"
}

@test "loki-infrastructure has logs of static pods" {
    _start_loki_infrastructure_port_forward
    containers_command="$(_loki_infrastructure_label_values_command container)"

    run --separate-stderr retry "$containers_command | grep --line-regexp --quiet kube-apiserver" 60
    assert_success
}

@test "loki-infrastructure has no tool logs" {
    _start_loki_infrastructure_port_forward
    namespaces_command="$(_loki_infrastructure_label_values_command namespace)"

    run --separate-stderr bash -c "$namespaces_command"
    assert_success
    # Make sure that the list is not empty, else the checks below always pass.
    assert_line "jobs-api"
    refute_line --regexp '^tool-'
    refute_line "image-build"
}

@test "a tool can not connect to loki-infrastructure" {
    TEST_JOB_NAME="test-$RANDOM"
    host="$LOKI_INFRASTRUCTURE_WRITE_SERVICE.loki.svc"
    # getent fails if the name does not resolve. Thus a wrong name does not
    # look like a blocked connection.
    check_command="getent hosts $host && if timeout 5 bash -c 'echo > /dev/tcp/$host/3100' 2>/dev/null; then echo 'loki-infrastructure reachable'; else echo 'loki-infrastructure blocked'; fi"

    sudo -i -u "$TEST_TOOL_UID" toolforge jobs run "$TEST_JOB_NAME" \
        --image python3.13 \
        --no-filelog \
        --wait 120 \
        --command "$check_command"

    run --separate-stderr retry "sudo -i -u '$TEST_TOOL_UID' toolforge jobs logs '$TEST_JOB_NAME' | grep 'loki-infrastructure '" 100
    assert_success
    assert_line --partial "loki-infrastructure blocked"
    refute_line --partial "loki-infrastructure reachable"
}

teardown() {
    _logging_teardown
}
