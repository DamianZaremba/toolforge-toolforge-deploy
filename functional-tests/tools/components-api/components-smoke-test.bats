#!/usr/bin/env bats
# shellcheck disable=SC2155
# SC2155 (warning): Declare and assign separately to avoid masking return values.
# bats file_tags=tools,components-api,smoke
set -o nounset

setup_file() {
    load "components-common"
    export BATS_NO_PARALLELIZE_WITHIN_FILE=true
    flush_everything
}

setup() {
    load "components-common"
    _components_setup
    export TOOL_NAME="${USER#*.}"

    if [[ "$PROJECT" == "tools" ]]; then
        skip "Skipping components tests until we have the cli deployed too"
    fi

    cat > "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml <<EOC
config_version: "v1beta1"
components:
  component1:
    component_type: continuous
    build:
      repository: $SAMPLE_REPO_URL
      ref: main
    run:
      command: web
EOC
    cat > "$BATS_FILE_TMPDIR"/dummy-ref-sourcebuild-test-config.yaml <<EOC
config_version: "v1beta1"
components:
  component1:
    component_type: continuous
    build:
      repository: $SAMPLE_REPO_URL
      ref: dummy_branch
    run:
      command: web
EOC
}

get_toolforge_url() {
    grep api_gateway -A 2 /etc/toolforge/common.yaml | grep url: | grep -o 'http.*$'
}

@test "config create works" {
    toolforge components config delete --yes-im-sure &>/dev/null || :
    run toolforge components config create "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml
    assert_success
}

@test "config show works" {
    toolforge components config delete --yes-im-sure &>/dev/null || :
    toolforge components config create "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml

    run toolforge components config show
    assert_success
    assert_line --partial "component1:"
}

@test "config update works" {
    run toolforge components config show
    assert_success
    assert_line --partial "ref: main"
    refute_line --partial "ref: dummy_branch"

    # update config
    run toolforge components config create "$BATS_FILE_TMPDIR"/dummy-ref-sourcebuild-test-config.yaml
    assert_success

    # ensure config now has the string "dummy_branch" not "main"
    run toolforge components config show
    assert_success
    refute_line --partial "ref: main"
    assert_line --partial "ref: dummy_branch"
}

@test "deploy token create works" {
    toolforge components deploy-token delete --yes-im-sure &>/dev/null || :
    run toolforge components deploy-token create
    assert_success
    assert_line --partial "Token:"
}

@test "deploy token show works" {
    toolforge components deploy-token delete --yes-im-sure &>/dev/null || :
    toolforge components deploy-token create

    run toolforge components deploy-token show
    assert_success
    assert_line --partial "Token:"
}

@test "deploy token refresh works" {
    local old_token=$(toolforge components deploy-token show --json | jq -r '.token')

    run toolforge components deploy-token refresh --yes-im-sure
    assert_success
    local new_token=$(echo "$output" | grep "Token:" | cut -d' ' -f2)
    assert_not_equal "$old_token" "$new_token"
}

@test "creating a deployment with invalid token fails" {
    local toolforge_url=$(get_toolforge_url)
    local invalid_token="3fae991e-193c-4b86-9f6a-im1nv4l1d"

    run bash -c "curl --insecure -X POST '$toolforge_url/components/v1/tool/$TOOL_NAME/deployment?token=$invalid_token' | jq"
    assert_success
    assert_line --partial "does not match the tool's token"
}

@test "can create deployment using the cli" {
    toolforge components config create "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml

    run toolforge components deployment create
    assert_success
    assert_line --partial "created successfully"

    local deployment_id=$(toolforge components deployment list --json | jq -r '.data.deployments[-1].deploy_id')

    retry "toolforge deployment show $deployment_id --json | jq -e '.status == \"running\"'" 20
}

@test "can create deployment using the token" {
    local toolforge_url=$(get_toolforge_url)
    local token=$(toolforge components deploy-token show --json | jq -r '.token')
    # we can only have one deployment at a time, so flush any existing deployments
    flush_deployments
    flush_builds

    run bash -c "curl --silent -v --insecure -X POST '$toolforge_url/components/v1/tool/$TOOL_NAME/deployment?token=$token' | jq -r .messages.info[0]"
    assert_success
    assert_line "Deployment for $TOOL_NAME created successfully."
}

@test "deployment list works" {
    run toolforge components deployment list
    assert_success
    assert_line --partial "ID"
    assert_line --partial "component1"
}

@test "deployment show works" {
    local deploy_id=$(toolforge components deployment list --json | jq -r '.data.deployments[-1].deploy_id')
    run toolforge components deployment show "$deploy_id"
    assert_success
    assert_line --partial "$deploy_id"
}

@test "deploy token delete works" {
    toolforge components deploy-token delete --yes-im-sure &>/dev/null || :
    toolforge components deploy-token create

    run toolforge components deploy-token delete --yes-im-sure
    assert_success

    run toolforge components deploy-token show
    assert_line --partial "Unable to find"
}

@test "deployment delete works" {
    local deploy_id=$(toolforge components deployment list --json | jq -r '.data.deployments[-1].deploy_id')
    run toolforge components deployment delete --yes-im-sure "$deploy_id"
    assert_success
    assert_line --partial "deleted successfully"
}

@test "config delete works" {
    toolforge components config delete --yes-im-sure &>/dev/null || :
    toolforge components config create "$BATS_FILE_TMPDIR"/main-ref-sourcebuild-test-config.yaml

    run toolforge components config delete --yes-im-sure
    assert_success

    run toolforge components config show
    refute_line --partial "components:"
}

teardown() {
    _components_teardown
}
