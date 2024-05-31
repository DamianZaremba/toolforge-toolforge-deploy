#!/usr/bin/env bats
# bats file_tags=jobs-api,smoke

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple one-off job" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --wait 120 \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'"
}


teardown() {
    _jobs_teardown
}
