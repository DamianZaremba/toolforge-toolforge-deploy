#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
}

# we are only testing update for now.
# Doesn't seem right to delete toolforge project (and potentially all the images and repos it might contain) just to test that maintain-harbor can recreate it.
@test "update toolforge project" {
    # make sure project already exists and up to date with config
    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-harbor-toolforge-project-cron"

    toolforge_project_name=$(echo "$HARBOR_CONFIGMAP" | jq '.data.MAINTAIN_HARBOR_TOOLFORGE_PROJECT | fromjson | .project_name')
    current_project=$($CURL -X GET "$HARBOR_URL/projects/$toolforge_project_name")
    modified_project=$(echo "$current_project" | jq '.metadata.public = "false"')

    # modify project
    $CURL -X PUT "$HARBOR_URL/projects/$toolforge_project_name" -d "$modified_project"

    # update project. This should reset project to the accepted configuration
    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-harbor-toolforge-project-cron"

    assert_success

    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"
    updated_project=$($CURL -X GET "$HARBOR_URL/projects/$toolforge_project_name")
    assert_equal "$(echo "$current_project" | jq -S .)" "$(echo "$updated_project" | jq -S .)"
}

teardown(){
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
    _maintain_harbor_teardown
}
