#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
}

@test "get harbor health without auth works" {
    run bash -c "curl --verbose --insecure '$HARBOR_URL/health'"
    assert_success
    assert_line --partial "200"
    assert_line --partial "],\"status\":\"healthy\"}"
}

@test "harbor authentication works" {

    run bash -c "$CURL_VERBOSE -X GET $HARBOR_URL/audit-logs"

    assert_success
    assert_line --partial "200" \
    "\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n
    Harbor authentication failed.\n
    You may need to verify that you have \"harbor-auth-secret\" k8s secret\n
    with data \"HARBOR_USERNAME\" and \"HARBOR_PASSWORD\" created for the test tool\n
    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
}

teardown() {
    _maintain_harbor_teardown
}
