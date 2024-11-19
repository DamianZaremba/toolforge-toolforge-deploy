#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple scheduled job" {
    rand_string="test-$RANDOM"
    run toolforge \
        jobs \
        run \
        --schedule '* * * * *' \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"
    assert_success

    # we need to wait tops a minute (and a bit more just in case)
    retry "grep '$rand_string' '$HOME/$rand_string.out'" 100
}


teardown() {
    _jobs_teardown
}
