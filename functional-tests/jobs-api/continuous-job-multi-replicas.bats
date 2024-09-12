#!/usr/bin/env bats
# bats file_tags=jobs-api

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a continuous job that defaults to 1 replica" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "while true; do sleep 10; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    run toolforge jobs show "$rand_string"
    assert_line --regexp 'Replicas:.*1'
}


@test "run a continuous job with 2 replicas configured" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "while true; do sleep 10; done" \
        --continuous \
        --replicas=2 \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    run toolforge jobs show "$rand_string"
    assert_line --regexp 'Replicas:.*2'
}


teardown() {
    _jobs_teardown
}
