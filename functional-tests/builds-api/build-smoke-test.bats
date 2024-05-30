#!/usr/bin/env bats
# bats file_tags=builds-api,smoke
SAMPLE_REPO_URL=https://gitlab.wikimedia.org/toolforge-repos/sample-static-buildpack-app


set -o nounset

setup() {
    load "../global-common"
    _global_setup
}


@test "start build" {
    toolforge build start --detach "$SAMPLE_REPO_URL"
}


@test "list build" {
    run toolforge build list
    assert_line --partial "$SAMPLE_REPO_URL"
}


# bats test_tags=slow
@test "tail logs and wait (slow)" {
    # this also waits for it to finish
    toolforge build logs -f
}


# bats test_tags=slow
@test "show finished build" {
    run toolforge build show
    assert_line --partial "Status: ok"
}


@test "delete build" {
    local build_id
    build_id="$(toolforge build list --json | jq -r '.build_id')"
    toolforge build delete --yes-i-know "$build_id"

    run toolforge build list
    refute_line --partial "$build_id"
    assert_line --partial "No builds found"
}


@test "quota" {
    run toolforge build quota
    assert_line --partial Available
    assert_line --partial Capacity
    assert_line --partial Limit
    assert_line --partial Used
}

@test "delete all" {
    toolforge build delete --all --yes-i-know
}


@test "clean" {
    toolforge build clean --yes-i-know
    run toolforge build list
    assert_line --partial "No builds found"
}


teardown() {
    _global_teardown
}
