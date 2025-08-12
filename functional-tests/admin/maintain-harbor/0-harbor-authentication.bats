#!/usr/bin/env bats
# bats file_tags=admin,maintain-harbor

set -o nounset

setup(){
    load "maintain-harbor-common"
    _maintain_harbor_setup
}

@test "get harbor health without auth works" {
    run bash -c "$CURL_VERBOSE_FAIL_WITH_BODY $HARBOR_URL/health"
    assert_success
    # Note that there's no `OK` in http2, and lima-kilo uses http1 while toolsbeta/tools uses http2
    assert_line --regexp "HTTP/.* 200"
    assert_line --partial "],\"status\":\"healthy\"}"
}

@test "harbor authentication works" {

    run bash -c "$CURL_VERBOSE_FAIL_WITH_BODY $HARBOR_URL/audit-logs"
    # Note that there's no `OK` in http2, and lima-kilo uses http1 while toolsbeta/tools uses http2
    if ! assert_line --regexp "HTTP.* 200"; then
        fail "\n@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@\n
            Harbor authentication failed.\n
            You may need to verify that you have \"harbor-auth-secret\" k8s secret\n
            with data \"HARBOR_USERNAME\" and \"HARBOR_PASSWORD\" created for the test tool\n
            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
    fi
}

teardown() {
    _maintain_harbor_teardown
}
