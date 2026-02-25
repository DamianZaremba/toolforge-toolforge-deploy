#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple continuous job with filelog, and check the logs" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run --separate-stderr toolforge \
        jobs \
        run \
        --filelog \
        --command "while true; do echo '$rand_string'; sleep 10; done" \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    retry "grep '$rand_string' '$HOME/$rand_string.out'"

    run toolforge jobs logs "$rand_string"
    assert_failure
    assert_line --partial "Job '$rand_string' does not have any logs available"
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

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"

    run --separate-stderr toolforge jobs logs "$rand_string" --last=1
    assert_success
    line_count=$(echo "$output" | grep -o "extraword-$rand_string" | wc -l)
    # check that only one line is returned
    [[ "$line_count" -eq 1 ]]
}


@test "run a simple continuous job without filelog and check the logs using --since and --until time" {
    rand_string="test-$RANDOM"
    # the weird command structure is so we can emit the logs in sync with the tick of each second by the clock
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
    run retry "toolforge jobs logs $rand_string" 100
    assert_success
    assert_line --partial "time-$rand_string"

    sleep 15 # intentionally longer than 5s to allow logs to be generated and scraped

    # test relative time
    run toolforge jobs logs "$rand_string" --since 6s --until 0s
    assert_success

    # check that we get between 5 and 6 lines, this should help avoid flakiness
    line_count=$(echo "$output" | grep -o "time-$rand_string" | wc -l)
    [[ "$line_count" -ge 5 ]]
    [[ "$line_count" -le 6 ]]

    since_time=$(date --utc --date='6 seconds ago' +'%Y-%m-%dT%H:%M:%SZ')
    until_time=$(date --utc +'%Y-%m-%dT%H:%M:%SZ')

    # test isoformat
    run toolforge jobs logs "$rand_string" --since "$since_time" --until "$until_time"
    assert_success
    line_count=$(echo "$output" | grep -o "time-$rand_string" | wc -l)
    [[ "$line_count" -ge 5 ]]
    [[ "$line_count" -le 6 ]]
}

@test "run a simple continuous job without filelog and check --since and --until validation errors" {
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
    run retry "toolforge jobs logs $rand_string | grep -q 'time-$rand_string'" 100
    assert_success

    run toolforge jobs logs "$rand_string" --since=invalid
    assert_line --partial 'Invalid "since" time'

    run toolforge jobs logs "$rand_string" --until=invalid
    assert_line --partial 'Invalid "until" time'

    run toolforge jobs logs "$rand_string" --since=10s --until=20s
    assert_line --partial '"since" time must be before "until" time'

    run toolforge jobs logs "$rand_string" --since=1999-01-01T00:00:00Z
    assert_line --partial 'the query time range exceeds the limit'

    run timeout 3 toolforge jobs logs "$rand_string" -f --since=100d
    assert_line --partial 'the query time range exceeds the limit'
}

teardown() {
    _jobs_teardown
}
