#!/usr/bin/env bats
# bats file_tags=tools,logs-api,smoke

set -o nounset

do_curl() {
    curl --verbose --insecure --cert "$HOME/.toolskube/client.crt" --key "$HOME/.toolskube/client.key" "$@" 2>&1
}
export -f do_curl

setup() {
    load "../../global-common"
    export TOOL_NAME="${USER#*.}"
    _global_setup
    rm -f test-* check-test-*
    toolforge jobs flush
}

@test "get logs from logs-api endpoint directly" {

    # create job to generate logs
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

    # Wait for logs to appear
    run retry "do_curl \"$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs\" | grep -q 'extraword-$rand_string'" 100
    assert_success

    run do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs"
    assert_success
    assert_line --partial "extraword-$rand_string"

    run do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/$rand_string/logs?lines=1"
    assert_success
    line_count=$(echo "$output" | grep -c "extraword-$rand_string")
    # check that only one line is returned
    [ "$line_count" -eq 1 ]
}

@test "get streaming logs from logs-api endpoint directly" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "while true; do echo 'streamword-$rand_string'; sleep 1; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    # Wait for logs to appear
    run retry "do_curl \"$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs\" | grep -q 'streamword-$rand_string'" 100
    assert_success

    # Check the logs-api stream endpoint
    # 10s so curl doesn't hang forever
    run do_curl --max-time 10 "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs_stream"
    assert_line --partial "streamword-$rand_string"
}

teardown() {
    _global_teardown
}
