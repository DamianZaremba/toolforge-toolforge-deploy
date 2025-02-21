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

@test "manage-harbor-projects-quotas job can be triggered successfully" {
    # trigger job and verify it runs to completion
    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-harbor-projects-quotas-cron"
    assert_success
    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"
}

@test "update if quota different from default" {
    quota=$($CURL -X GET "$HARBOR_URL/quotas?page_size=-1" | jq -r ".[] | select(.ref.name == \"$HARBOR_PROJECT_NAME\")")
    quota_id=$(echo "$quota" | jq -r '.id')

    # update quota to a value different from default
    quota=$(echo "$quota" | jq '.hard.storage = 100')
    $CURL -X PUT "$HARBOR_URL/quotas/$quota_id" -d "$quota"

    # verify that the new value is now 100
    quota=$($CURL -X GET "$HARBOR_URL/quotas/$quota_id")
    assert_equal "$(echo "$quota" | jq -r '.hard.storage')" "100"

    # trigger job and verify that the quota is reset to default
    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-harbor-projects-quotas-cron"
    assert_success
    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"
    quota=$($CURL -X GET "$HARBOR_URL/quotas/$quota_id")
    assert_not_equal "$(echo "$quota" | jq -r '.hard.storage')" "100"
}

@test "update if quota different from override" {
    # get current quota
    quota=$($CURL -X GET "$HARBOR_URL/quotas?page_size=-1" | jq -r ".[] | select(.ref.name == \"$HARBOR_PROJECT_NAME\")")
    quota_id=$(echo "$quota" | jq -r '.id')
    assert_not_equal "$(echo "$quota" | jq -r '.hard.storage')" "1000"

    # add override to the configmap
    harbor_config_with_override=$(echo "$HARBOR_CONFIGMAP" | jq '.data.MAINTAIN_HARBOR_PROJECT_QUOTA |= (fromjson | .overrides["'"$HARBOR_PROJECT_NAME"'"] = 1000 | tojson)')
    run bash -c "echo '$harbor_config_with_override' | $SUKUBECTL replace -f -"
    assert_success

    # trigger job and verify that override is applied
    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-harbor-projects-quotas-cron"
    assert_success
    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"
    quota=$($CURL -X GET "$HARBOR_URL/quotas/$quota_id")
    assert_equal "$(echo "$quota" | jq -r '.hard.storage')" "1000"
}

teardown(){
    echo "$HARBOR_CONFIGMAP" | $SUKUBECTL replace --force -f - || :
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
    _maintain_harbor_teardown
}
