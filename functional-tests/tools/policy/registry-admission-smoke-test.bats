#!/usr/bin/env bats
# bats file_tags=tools,policy,smoke

set -o nounset

setup() {
    load "../../global-common"
    _global_setup
}

@test "verify the registry admission is not allowing arbitrary registries in a deploy" {
    # with --restart=Always it creates a Deployment resource
    run kubectl run nginx --image=nginx --restart=Always
    assert_line --partial "Error from server: admission webhook \"registry-admission.tools.wmcloud.org\" denied the request"
    assert_failure
}

@test "verify the registry admission is not allowing arbitrary registries in a pod" {
    # with --restart=Never it creates a Pod resource
    run kubectl run nginx --image=nginx --restart=Never
    assert_line --partial "Error from server: admission webhook \"registry-admission.tools.wmcloud.org\" denied the request"
    assert_failure
}
