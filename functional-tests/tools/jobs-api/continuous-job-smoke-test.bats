#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple continuous job" {
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

    retry "grep '$rand_string' '$HOME/$rand_string'"
}

teardown() {
    _jobs_teardown
}
