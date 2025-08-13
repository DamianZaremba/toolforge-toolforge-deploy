#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
}

@test "delete stale toolforge artifacts" {
    job_name="test-$RANDOM"
    # shellcheck disable=SC2086
    run --separate-stderr $SUKUBECTL create job "$job_name" --from=cronjob/mh--delete-stale-toolforge-artifacts-cron
    assert_success

    retry "$SUKUBECTL get pods -o name | grep -q \"$job_name\"" 60
    # shellcheck disable=SC2086
    pod=$($SUKUBECTL get pods -o name | grep "$job_name")
    # shellcheck disable=SC2086
    run --separate-stderr retry "$SUKUBECTL logs --follow '$pod'"
    assert_success

    assert_line --regexp "Cleaning up stale artifacts of toolforge project repositories"
    assert_line --regexp "Got .* repositories for project .*"
    assert_line --regexp "Found .* toolforge project repositories with stale artifacts"
    assert_line --regexp "Disabled immutable rule .* for project .*"
    assert_line --regexp "Enabled immutable rule .* project .*"
}

teardown(){
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
    _maintain_harbor_teardown
}
