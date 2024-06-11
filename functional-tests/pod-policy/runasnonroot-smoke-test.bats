#!/usr/bin/env bats
# bats file_tags=pod-policy,smoke

set -o nounset

setup() {
    load "../global-common"
    _global_setup
}

@test "verify the runAsNonRoot pod policy is acting" {
    filename="$BATS_TEST_DIRNAME/pod-policy-runAsNonRoot.yaml"
    podname="functional-tests-pod-policy-runasnonroot"

    # cleanup pre-run
    kubectl delete pod "$podname" || true

    # load potentially offending pod
    run kubectl apply -f "$filename"
    assert_line --partial "rule toolforge-validate-pod-policy failed at path /spec/securityContext/runAsNonRoot/"
    assert_failure
}
