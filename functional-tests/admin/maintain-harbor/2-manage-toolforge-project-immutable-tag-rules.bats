#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
}

@test "create toolforge project immutable tags" {
    toolforge_project_name=$(echo "$HARBOR_CONFIGMAP" | jq -r '.data.MAINTAIN_HARBOR_TOOLFORGE_PROJECT | fromjson | .project_name')
    configured_immutable_tag_rules=$(echo "$HARBOR_CONFIGMAP" | jq '.data.MAINTAIN_HARBOR_TOOLFORGE_PROJECT | fromjson | .immutable_tag_rules')

    # loop over current_project_immutable_rules and delete them
    current_project_immutable_rules=$($CURL -X GET "$HARBOR_URL/projects/$toolforge_project_name/immutabletagrules?page_size=-1")
    for immutable_rule_id in $(echo "$current_project_immutable_rules" | jq -r '.[].id'); do
        run bash -c "$CURL_VERBOSE_FAIL_WITH_BODY -X DELETE \"$HARBOR_URL/projects/$toolforge_project_name/immutabletagrules/$immutable_rule_id\""
    done

    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-toolforge-proj-immutable-tag-rules-cron"
    assert_success
    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"

    # check that updated_project_immutable_rules is same length as configured_immutable_tag_rules
    updated_project_immutable_rules=$($CURL -X GET "$HARBOR_URL/projects/$toolforge_project_name/immutabletagrules?page_size=-1")
    assert_equal "$(echo "$updated_project_immutable_rules" | jq 'length')" "$(echo "$configured_immutable_tag_rules" | jq 'length')"
}

@test "update toolforge project immutable rules" {
    toolforge_project_name=$(echo "$HARBOR_CONFIGMAP" | jq -r '.data.MAINTAIN_HARBOR_TOOLFORGE_PROJECT | fromjson | .project_name')
    configured_immutable_tag_rules=$(echo "$HARBOR_CONFIGMAP" | jq '.data.MAINTAIN_HARBOR_TOOLFORGE_PROJECT | fromjson | .immutable_tag_rules')

    # loop over current_project_immutable_rules and modify them
    current_project_immutable_rules=$($CURL -X GET "$HARBOR_URL/projects/$toolforge_project_name/immutabletagrules?page_size=-1")
    echo "$current_project_immutable_rules" | jq -c '.[]' | while read -r immutable_rule; do
        immutable_rule_id=$(echo "$immutable_rule" | jq '.id')
        modified_project_immutable_rule=$(echo "$immutable_rule" | jq ".disabled = true")
        $CURL -X PUT "$HARBOR_URL/projects/$toolforge_project_name/immutabletagrules/$immutable_rule_id" -d "$modified_project_immutable_rule"
    done

    # update toolforge project immutable tag rules. This should reset rules to configured values
    job_name="test-$RANDOM"
    run bash -c "$SUKUBECTL create job \"$job_name\" --from=cronjob/mh--manage-toolforge-proj-immutable-tag-rules-cron"

    assert_success
    retry "$SUKUBECTL get pods | grep \"$job_name\" | grep 'Completed'"

    updated_immutable_tag_rules=$($CURL -X GET "$HARBOR_URL/projects/$toolforge_project_name/immutabletagrules?page_size=-1")
    # check that updated_immutable_tag_rules is same length as configured_immutable_tag_rules
    assert_equal "$(echo "$configured_immutable_tag_rules" | jq 'length')" "$(echo "$updated_immutable_tag_rules" | jq 'length')"

    rule_count=$(echo "$configured_immutable_tag_rules" | jq 'length')
    # Use a C-style for loop to iterate using an index
    for (( i=0; i<rule_count; i++ )); do
        configured_rule=$(echo "$configured_immutable_tag_rules" | jq -c ".[$i]")
        updated_rule=$(echo "$updated_immutable_tag_rules" | jq -c ".[$i]")

        assert_equal "$(echo "$configured_rule" | jq '.disabled')" "$(echo "$updated_rule" | jq '.disabled')"
    done
}

teardown(){
    $SUKUBECTL delete jobs --all --grace-period 0 --force 2>/dev/null || :
    _maintain_harbor_teardown
}
