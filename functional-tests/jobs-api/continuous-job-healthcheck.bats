#!/usr/bin/env bats
# bats file_tags=jobs-api

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a continuous job with script healthcheck passing" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "echo 'ok' > /tmp/healthcheck; while true; do sleep 10; done" \
        --continuous \
        --health-check-script 'grep ok /tmp/healthcheck' \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'"
}


@test "run a continuous job with script healthcheck failing" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "while true; do sleep 10; done" \
        --continuous \
        --health-check-script '[[ -e /idontexist ]]' \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    # TODO: Find a faster way to check this
    run retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 10
    assert_failure
}


teardown() {
    _jobs_teardown
}
