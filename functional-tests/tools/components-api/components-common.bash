#!/usr/bin/env bash

_components_setup() {
    load "../../global-common"
    _global_setup
    export SAMPLE_REPO_URL=https://gitlab.wikimedia.org/toolforge-repos/sample-static-buildpack-app

}

_components_teardown() {
    _global_teardown
}

flush_builds() {
    toolforge build delete --yes-i-know --all &>/dev/null || :
}

flush_jobs() {
    toolforge jobs flush &>/dev/null || :
}

flush_deployments() {
    local deploy_id
    toolforge components deployment list --json 2>/dev/null | \
    jq -r '.data.deployments[].deploy_id' |  \
    while IFS= read -r deploy_id; do
        toolforge components deployment delete --yes-im-sure "$deploy_id" &>/dev/null  || :
    done
}

flush_everything() {
    flush_jobs
    flush_builds
    flush_deployments
    toolforge components config delete --yes-im-sure &>/dev/null || :
    toolforge components deploy-token delete --yes-im-sure &>/dev/null || :
}

create_deployment() {
    bats_pipe toolforge components deployment create --json \| jq -r .data.deploy_id
    assert_success
}

wait_for_successful_deployment() {
    local deployment_id="${1}"

    # Verify we have been passed a deployment id, if not then fail early
    assert_not_equal "${deployment_id}" ""

    # Wait for the deployment to transition into a final state
    retry "toolforge components deployment show $deployment_id --json | jq -e '.status | IN (\"pending\", \"running\") | not'" 300

    # Check the final state is successful
    run --separate-stderr bash -c "toolforge components deployment show $deployment_id --json | jq -r .status"
    assert_success
    assert_line "successful"
}

teardown() {
    _components_teardown
}
