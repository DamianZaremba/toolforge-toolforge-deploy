#!/usr/bin/env bats
# bats file_tags=tools,builds-api,smoke
SAMPLE_REPO_URL=https://gitlab.wikimedia.org/toolforge-repos/sample-static-buildpack-app


set -o nounset

setup() {
    load "../../global-common"
    _global_setup
}


setup_file() {
    # cleanup just in case
    toolforge build delete --all --yes-i-know 2>/dev/null || :
    toolforge build clean --yes-i-know 2>/dev/null || :
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
    toolforge build logs -f
}


# bats test_tags=slow
@test "show finished build (slow)" {
    # the build may download a bunch of stuff from the internet
    # retry in case the build takes time to complete and update the Status field
    retry "toolforge build show | grep 'Status: ok'"
}


@test "run job with built image" {
    rand_string="test-$RANDOM"
    # need the mount=all for the results
    user="${USER#*.}"
    image="tool-$user/tool-$user:latest"
    toolforge \
        jobs \
        run \
        --wait 120 \
        --command="echo '$rand_string' | tee \$TOOL_DATA_DIR/$rand_string.out" \
        --mount=all \
        --image="$image" \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'"
}


@test "delete build" {
    local build_id
    build_id="$(toolforge build list --json | jq -r '.builds[0].build_id')"
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
