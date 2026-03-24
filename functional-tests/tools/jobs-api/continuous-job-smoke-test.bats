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
    line_count=$(echo "$output" | grep -c "extraword-$rand_string")
    # check that only one line is returned
    [ "$line_count" -eq 1 ]
}


teardown() {
    _jobs_teardown
}
