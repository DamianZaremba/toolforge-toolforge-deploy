#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple scheduled job with filelog, and check the logs" {
    rand_string="test-$RANDOM"
    run --separate-stderr toolforge \
        jobs \
        run \
        --filelog \
        --schedule '* * * * *' \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"
    assert_success

    # we need to wait tops a minute (and a bit more just in case)
    retry "grep '$rand_string' '$HOME/$rand_string.out'" 100
}

@test "run a simple scheduled job without filelog, and check the logs" {
    rand_string="test-$RANDOM"
    run --separate-stderr toolforge \
        jobs \
        run \
        --no-filelog \
        --schedule '* * * * *' \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"
    assert_success

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_line --partial "$rand_string"
}


teardown() {
    _jobs_teardown
}
