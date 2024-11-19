#!/usr/bin/env bats
# bats file_tags=tools,jobs-api

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a continuous job without port shows no port" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "while true; do echo '$rand_string' > '$rand_string'; sleep 10; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    run toolforge jobs show "$rand_string"
    assert_line --regexp 'Port:.*none'
}

@test "run a continuous job with a port shows port" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --command "while true; do echo '$rand_string' > '$rand_string'; sleep 10; done" \
        --port=1234 \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run toolforge jobs show "$rand_string"
    assert_line --regexp 'Port:.*1234'
}

@test "run a continuous job with a port exposes port" {
    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 1234" \
        --port=1234 \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'"

    toolforge jobs run \
        --command "curl -v 'http://$rand_string.tool-$tool_name.svc.$CLUSTER_DOMAIN:1234/status'" \
        --wait 120 \
        --image python3.11 \
        check-$rand_string

    run cat "check-$rand_string.out"
    assert_line "OK"
}


teardown() {
    _jobs_teardown
}
