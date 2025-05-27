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


teardown() {
    _components_teardown
}
