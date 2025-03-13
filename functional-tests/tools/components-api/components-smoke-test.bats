#!/usr/bin/env bats
# bats file_tags=tools,components-api,smoke

set -o nounset

setup() {
    load "components-common"
    _components_setup
    export TOOL_NAME="${USER#*.}"

    if [[ "$PROJECT" == "tools" ]]; then
        skip "Skipping components tests"
    fi
}

setup_file() {
    # cleanup just in case
    toolforge components config delete --yes-im-sure &>/dev/null || true
    toolforge components deploy-token delete --yes-im-sure &>/dev/null || true
    for deploy_id in $(toolforge components deployment list --json | jq -r '.data.deployments[].deploy_id' 2>/dev/null); do
        toolforge components deployment delete --yes-im-sure "$deploy_id" &>/dev/null || true
    done

    echo "config_version: \"silly\"
components:
  component1:
    component_type: continuous
    build:
      use_prebuilt: python3.11
    run:
      command: while date; do sleep 1; done" > test-config.yaml
}

get_toolforge_url() {
    grep api_gateway -A 2 /etc/toolforge/common.yaml | grep url: | grep -o 'http.*$'
}


@test "config create works" {
    run toolforge components config create test-config.yaml
    assert_success
}

@test "config show works" {
    run toolforge components config show
    assert_success
    assert_line --partial "component1"
}

@test "config update works" {
    echo "config_version: \"silly\"
components:
  component1:
    component_type: continuous
    build:
      use_prebuilt: python3.11
    run:
      command: while date; do sleep 5; done" > test-config.yaml

    run toolforge components config create test-config.yaml
    assert_success

    run toolforge components config show
    assert_success
    assert_line --partial "sleep 5"
}

@test "deploy token create works" {
    run toolforge components deploy-token create
    assert_success
    assert_line --partial "Token:"
}

@test "deploy token show works" {
    run toolforge components deploy-token show
    assert_success
    assert_line --partial "Token:"
}

@test "deploy token refresh works" {
    run toolforge components deploy-token show
    old_token=$(echo "$output" | grep "Token:" | cut -d' ' -f2)

    run toolforge components deploy-token refresh --yes-im-sure
    assert_success
    new_token=$(echo "$output" | grep "Token:" | cut -d' ' -f2)
    [ "$old_token" != "$new_token" ]
}

@test "can create deployment using the cli" {
    run toolforge components deployment create
    assert_success
    assert_line --partial "created successfully"
}

@test "can create deployment using the token" {
    toolforge_url=$(get_toolforge_url)
    token=$(toolforge components deploy-token show | grep "Token:" | cut -d' ' -f2)

    run bash -c "curl --insecure -X POST '$toolforge_url/components/v1/tool/$TOOL_NAME/deployment?token=$token' | jq"
    assert_success
    assert_line --partial "created successfully"
}

@test "deployment with invalid token fails" {
    toolforge_url=$(get_toolforge_url)
    invalid_token="3fae991e-193c-4b86-9f6a-445c0dfd093e"

    run bash -c "curl --insecure -X POST '$toolforge_url/components/v1/tool/$TOOL_NAME/deployment?token=$invalid_token' | jq"
    assert_success
    assert_line --partial "does not match the tool's token"
}

@test "deployment list works" {
    run toolforge components deployment list
    assert_success
    assert_line --partial "ID"
    assert_line --partial "component1"
}

@test "deployment show works" {
    deploy_id=$(toolforge components deployment list --json | jq -r '.data.deployments[0].deploy_id')
    run toolforge components deployment show "$deploy_id"
    assert_success
    assert_line --partial "$deploy_id"
}

@test "deployment delete works" {
    deploy_id=$(toolforge components deployment list --json | jq -r '.data.deployments[0].deploy_id')
    run toolforge components deployment delete --yes-im-sure "$deploy_id"
    assert_success
    assert_line --partial "deleted successfully"
}

@test "config delete works" {
    run toolforge components config delete --yes-im-sure
    assert_success

    run toolforge components config show
    refute_line --partial "components:"
}

@test "deploy token delete works" {
    run toolforge components deploy-token delete --yes-im-sure
    assert_success

    run toolforge components deploy-token show
    assert_line --partial "Unable to find"
}

teardown() {
    rm -f test-config.yaml
    toolforge jobs delete component1 &>/dev/null || :
    _components_teardown
}
