#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple continuous job with filelog, and check the logs" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run --separate-stderr toolforge \
        jobs \
        run \
        --filelog \
        --command "while true; do echo '$rand_string'; sleep 10; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    retry "grep '$rand_string' '$HOME/$rand_string.out'"
}


@test "run a simple continuous job without filelog, and check the logs" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "while true; do echo '$rand_string'; sleep 10; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_line --partial "$rand_string"
}


teardown() {
    _jobs_teardown
}
