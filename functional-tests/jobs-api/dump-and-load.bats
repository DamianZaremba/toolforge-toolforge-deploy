#!/usr/bin/env bats
# bats file_tags=jobs-api

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "do a simple dump and load" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --schedule '* * * * *' \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"

    toolforge jobs dump > "$rand_string.yaml"
    toolforge jobs flush

    run toolforge jobs list -o name
    assert_output ""

    toolforge jobs load "$rand_string.yaml"

    run toolforge jobs list -o name
    assert_output "$rand_string"
}


@test "doing a load does not flush all other jobs (T364204)" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --schedule '* * * * *' \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"
    toolforge jobs dump > "$rand_string.yaml"
    toolforge jobs flush

    rand_string2="test2-$RANDOM"
    toolforge \
        jobs \
        run \
        --schedule '* * * * *' \
        --command "echo '$rand_string2'" \
        --image=python3.11 \
        "$rand_string2"

    run toolforge jobs list -o name
    assert_output --partial "$rand_string2"

    toolforge jobs load "$rand_string.yaml"

    run toolforge jobs list -o name
    assert_line "$rand_string"
    assert_line "$rand_string2"
}



teardown() {
    _jobs_teardown
}
