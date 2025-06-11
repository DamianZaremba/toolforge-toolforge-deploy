#!/usr/bin/env bats
# bats file_tags=tools,jobs-api

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "do a simple dump and load of scheduled job" {
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


@test "do a simple dump and load of continuous job" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --continuous \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        --health-check-script "true" \
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

@test "jobs-load only updates existing jobs if important fields changed" {
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

    run toolforge jobs load "$rand_string.yaml"
    assert_line --partial "created"
    run toolforge jobs list -o name
    assert_output "$rand_string"

    run toolforge jobs load "$rand_string.yaml"
    assert_line --partial "already up to date"
    run toolforge jobs list -o name
    assert_output "$rand_string"

    sed -i "s|\* \* \* \* \*|*/5 * * * *|" "$rand_string.yaml"
    run toolforge jobs load "$rand_string.yaml"
    assert_line --partial "updated"
    run toolforge jobs list -o name
    assert_output "$rand_string"

}


teardown() {
    _jobs_teardown
}
