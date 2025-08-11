#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
}

@test "delete image retention" {
    retention_id=$($CURL -X GET "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME" | jq -r '.metadata.retention_id')

    # Delete retention policy
    if [ "$retention_id" != "null" ]; then
        run bash -c "$CURL_VERBOSE -X DELETE \"$HARBOR_URL/retentions/$retention_id\""
        # Note that there's no `OK` in http2
        assert_line --regexp "HTTP/2 200|no such Retention policy with id"
    fi

    # Get all project repositories
    repos=$($CURL -X GET "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME/repositories" | jq -r '.')

    # loop through repos and delete all
    for path in $(echo "$repos" | jq -r '.[].name'); do
        path="${path//\//\/repositories\/}"
        run --separate-stderr bash -c "$CURL_VERBOSE_FAIL_WITH_BODY -X DELETE \"$HARBOR_URL/projects/$path\""
    done

    # Delete project
    run --separate-stderr bash -c "$CURL_VERBOSE_FAIL_WITH_BODY -X DELETE \"$HARBOR_URL/projects/$HARBOR_PROJECT_NAME\""
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

@test "create image retention" {
    job_name="test-$RANDOM"
    run --separate-stderr bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-image-retention-cron"

    assert_success

    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"

    retention_id=$($CURL -X GET "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME" | jq '.metadata.retention_id')

    assert_not_equal "$retention_id" "null"
}

@test "update image retention" {
    retention_id=$($CURL -X GET "$HARBOR_URL/projects/$HARBOR_PROJECT_NAME" | jq -r '.metadata.retention_id')

    retention=$($CURL -X GET "$HARBOR_URL/retentions/$retention_id")

    modified_retention=$(echo "$retention" | jq '.algorithm = "and"')

    # modify retention policy
    $CURL -X PUT "$HARBOR_URL/retentions/$retention_id" -d "$modified_retention"

    # update retention policy. This should reset retention policy to the accepted value
    job_name="test-$RANDOM"
    run --separate-stderr bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-image-retention-cron"

    assert_success

    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"

    updated_retention=$($CURL -X GET "$HARBOR_URL/retentions/$retention_id")

    assert_equal "$(echo "$retention" | jq -S .)" "$(echo "$updated_retention" | jq -S .)"
}

teardown(){
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
    _maintain_harbor_teardown
}
