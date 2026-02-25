#!/usr/bin/env bats
# bats file_tags=tools,logs-api,smoke

set -o nounset

do_curl() {
    curl --insecure --cert "$HOME/.toolskube/client.crt" --key "$HOME/.toolskube/client.key" "$@" 2>&1
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

    run --separate-stderr do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs"
    assert_success
    assert_line --partial "extraword-$rand_string"

    run --separate-stderr do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/$rand_string/logs?lines=1"
    assert_success
    line_count=$(echo "$output" | grep -o "extraword-$rand_string" | wc -l)
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
    run --separate-stderr do_curl --max-time 10 "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs_stream"
    assert_line --partial "streamword-$rand_string"
}

@test "get logs from logs-api endpoint directly with start and end params" {
    rand_string="test-$RANDOM"
    # the weird command structure below is so we can emit the logs in sync with the tick of each second by the clock
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "while true; do echo 'time-$rand_string'; sleep \$(date +%s.%N | awk '{print 1 - (\$1 % 1)}'); done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    # Wait for logs to appear
    run retry "do_curl \"$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs\" | grep -q 'time-$rand_string'" 100
    assert_success

    sleep 15 # intentionally longer than 5s to allow logs to be generated and scraped

    # test relative time
    run --separate-stderr do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs?start=6s&end=0s"
    assert_success

    # check that we get between 5 and 6 lines, this should help avoid flakiness
    line_count=$(echo "$output" | grep -o "time-$rand_string" | wc -l)
    [ "$line_count" -ge 5 ]
    [ "$line_count" -le 6 ]

    start_time=$(date --utc --date='6 seconds ago' +'%Y-%m-%dT%H:%M:%SZ')
    end_time=$(date --utc +'%Y-%m-%dT%H:%M:%SZ')

    # test isoformat
    run --separate-stderr do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs?start=$start_time&end=$end_time"
    assert_success
    line_count=$(echo "$output" | grep -o "time-$rand_string" | wc -l)
    [ "$line_count" -ge 5 ]
    [ "$line_count" -le 6 ]
}

@test "get logs from logs-api endpoint fails for invalid start and/or end params" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "while true; do echo 'time-$rand_string'; sleep 1; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    # Wait for logs to appear
    run retry "do_curl \"$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs\" | grep -q 'time-$rand_string'" 100
    assert_success

    run do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs?start=invalid"
    assert_success
    assert_line --partial "Invalid start time"

    run do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs?end=invalid"
    assert_success
    assert_line --partial "Invalid end time"

    run do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs?start=10s&end=20s"
    assert_success
    assert_line --partial "Start time must be before end time"

    run do_curl "$TOOLFORGE_API_URL/logs/v1/tool/$TOOL_NAME/job/$rand_string/logs_stream?start=invalid"
    assert_success
    assert_line --partial "Invalid start time"
}

teardown() {
    _global_teardown
}
