#!/usr/bin/env bats
# bats file_tags=tools,logs-api,smoke

set -o nounset

setup() {
    load "logs-common"
    _logs_setup
}


@test "run a simple continuous job without filelog, and check the jobs source" {
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

    run toolforge logs --job-names="$rand_string" --source=jobs
    assert_success

    assert_line --partial "JOB CREATED: job 'test-$rand_string' created by user 'service:jobs-api', with message (format: json)"
}


teardown() {
    _logs_teardown
}
