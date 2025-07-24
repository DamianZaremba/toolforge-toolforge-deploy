#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
}

# bats test_tags=slow
@test "create a build (slow)" {
    artifacts=$($CURL "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME/repositories/$HARBOR_PROJECT_NAME/artifacts")

    # can be empty array if repo or artifacts doesn't exist, or error if project doesn't exist.
    # create build it build doesn't exist
    if [[ "$artifacts" == "[]" || "$artifacts" == *"forbidden"* ]]; then
        sudo -i -u "$TEST_TOOL_UID" toolforge build start "$SAMPLE_REPO_URL"
        retry "sudo -i -u \"$TEST_TOOL_UID\" toolforge build show | grep 'Status: ok'"
    fi
}

@test "delete project repositories" {
    # Get all project repositories
    repos=$($CURL -X GET "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME/repositories" | jq -r '.')

    # loop through repos and delete all
    for path in $(echo "$repos" | jq -r '.[].name'); do
        path="${path//\//\/repositories\/}"
        run --separate-stderr bash -c "$CURL_VERBOSE_FAIL_WITH_BODY -X DELETE \"$HARBOR_URL/projects/$path\""
    done

    # Check if all repos are deleted
    repo_count=$($CURL -X GET "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME" | jq -r '.repo_count')
    assert_equal "$repo_count" "0"
}

@test "delete empty harbor tool project" {
    job_name="test-$RANDOM"
    run --separate-stderr bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--delete-empty-tool-projects-cron"

    assert_success

    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"

    run --separate-stderr bash -c "$CURL -X GET \"$HARBOR_URL/projects\" | jq -r '.'"

    assert_success
    refute_line --partial "\"name\": \"$HARBOR_PROJECT_NAME\""
}

teardown(){
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
    _maintain_harbor_teardown
}
