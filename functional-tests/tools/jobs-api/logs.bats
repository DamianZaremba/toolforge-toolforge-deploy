#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke,logs

set -o nounset

do_curl() {
    curl --verbose --insecure --cert "$HOME/.toolskube/client.crt" --key "$HOME/.toolskube/client.key" "$@" 2>&1
}
export -f do_curl

setup() {
    load "jobs-common"
    load "../../global-common"
    export TOOL_NAME="${USER#*.}"
    _global_setup
    _jobs_setup
}

@test "run a simple continuous job with filelog, and check the logs" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run --separate-stderr toolforge \
        jobs \
        run \
        --filelog \
        --command "while true; do echo '$rand_string'; sleep 1; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    retry "grep '$rand_string' '$HOME/$rand_string.out'"

    run do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/$rand_string/logs"
    assert_success
    assert_line --partial "'$rand_string' has file logging enabled"
}


@test "run a simple continuous job without filelog, and check the logs" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "while true; do echo 'extraword-$rand_string'; sleep 1; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run retry "toolforge jobs logs $rand_string" 100
    assert_success
    assert_line --partial "extraword-$rand_string"

    run do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/$rand_string/logs"
    assert_success
    assert_line --partial "extraword-$rand_string"

    run do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/$rand_string/logs?lines=1"
    assert_success
    line_count=$(echo "$output" | grep -c "extraword-$rand_string")
    # check that only one line is returned
    [ "$line_count" -eq 1 ]

    run do_curl --max-time 10 "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/$rand_string/logs?follow=true"
    assert_line --partial "extraword-$rand_string"
}

teardown() {
    _jobs_teardown
    _global_teardown
}
