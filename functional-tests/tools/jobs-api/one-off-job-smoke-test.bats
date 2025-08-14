#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple one-off job with filelog, and check the logs" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --filelog \
        --wait 120 \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'" 100
}


@test "run a simple one-off job without filelog, and check the logs" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo '$rand_string'; sleep 1; done" \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_line --partial "$rand_string"
}


teardown() {
    _jobs_teardown
}
