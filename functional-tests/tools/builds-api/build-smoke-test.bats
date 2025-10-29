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
    run --separate-stderr toolforge build list
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
    command="echo '$rand_string' | tee \$TOOL_DATA_DIR/$rand_string.out"
    toolforge \
        jobs \
        run \
        --wait 120 \
        --command="$command" \
        --mount=all \
        --image="$image" \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'"
    # the `launcher` prefix is not shown in the job list/show, only from k8s
    run --separate-stderr bash -c "kubectl get pod -l "app.kubernetes.io/name=$rand_string" -o json | jq '.items[0].spec.containers[0].command[-1]'"
    assert_line --partial "launcher $command"
}


@test "ensure default mount is none for buildservice image" {
    rand_string="test-$RANDOM"
    user="${USER#*.}"
    image="tool-$user/tool-$user:latest"
    toolforge \
        jobs \
        run \
        --command="date" \
        --image="$image" \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"

    assert_line --regexp 'Mounts: *| none'
}


@test "ensure mount=all sets the mount all for buildservice image" {
    rand_string="test-$RANDOM"
    user="${USER#*.}"
    image="tool-$user/tool-$user:latest"
    toolforge \
        jobs \
        run \
        --command="date" \
        --mount=all \
        --image="$image" \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"

    assert_line --regexp 'Mounts: *| all'
}


@test "ensure mount=none sets mount none for buildservice image" {
    rand_string="test-$RANDOM"
    user="${USER#*.}"
    image="tool-$user/tool-$user:latest"
    toolforge \
        jobs \
        run \
        --command="date" \
        --mount=none \
        --image="$image" \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"

    assert_line --regexp 'Mounts: *| none'
}


@test "delete build" {
    local build_id
    build_id="$(toolforge build list --json | jq -r '.builds[0].build_id')"
    toolforge build delete --yes-i-know "$build_id"

    run --separate-stderr toolforge build list
    refute_line --partial "$build_id"
    assert_line --partial "No builds found"
}


@test "quota" {
    run --separate-stderr toolforge build quota
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
    run --separate-stderr toolforge build list
    assert_line --partial "No builds found"
}


teardown() {
    _global_teardown
}
