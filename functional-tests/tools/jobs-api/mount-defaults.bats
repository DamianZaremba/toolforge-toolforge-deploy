#!/usr/bin/env bats
# bats file_tags=tools,jobs-api

set -o nounset


setup() {
    load "jobs-common"
    export MIN_BATS_VERSION=1.5.0
    _jobs_setup
}

# For the tests with built images, see under builds-api as they require building one first

@test "ensure default mount is all for pre-built images" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --command="date" \
        --image="python3.13" \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"

    assert_line --regexp 'Mounts: *| all'
}


@test "ensure mount=none fails for pre-built images" {
    rand_string="test-$RANDOM"
    run toolforge \
        jobs \
        run \
        --command="date" \
        --image="python3.13" \
        --no-filelog \
        --mount=none \
        "$rand_string"

    assert_line --partial 'Mount type none is only supported for build service images'
}


@test "ensure mount=all sets the mount for pre-built images" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --command="date" \
        --image="python3.13" \
        --mount=all \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"

    assert_line --regexp 'Mounts: *| all'
}

teardown() {
    _jobs_teardown
}
