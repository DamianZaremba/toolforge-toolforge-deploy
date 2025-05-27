#!/usr/bin/env bats
# bats file_tags=tools,direct-api,smoke


set -o nounset

setup() {
    load "../../global-common"
    export TOOL_NAME="${USER#*.}"
    _global_setup
}


do_curl() {
    curl \
        --verbose \
        --insecure \
        --cert ~/.toolskube/client.crt \
        --key ~/.toolskube/client.key \
        "$@" \
        2>&1
}


@test "get openapi definition" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars openapi definition without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/envvars/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars metrics without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/envvars/v1/metrics'"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars health without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/envvars/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars list for current tool works" {
    run do_curl "$TOOLFORGE_API_URL/envvars/v1/tool/$TOOL_NAME/envvars"
    assert_line --partial "200 OK"
}

@test "get envvars list for other tool fails with forbidden" {
    run do_curl "$TOOLFORGE_API_URL/envvars/v1/tool/$TOOL_NAME.notthistool/envvars"
    assert_line --partial "403 Forbidden"
}

@test "get jobs openapi definition without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/jobs/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get jobs metrics without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/jobs/v1/metrics'"
    assert_success
    assert_line --partial "200 OK"
}


@test "get jobs health without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/jobs/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}

@test "get jobs list for current tool works" {
    run do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME/jobs/"
    assert_line --partial "200 OK"
}

@test "get jobs list for other tool fails with forbidden" {
    run do_curl "$TOOLFORGE_API_URL/jobs/v1/tool/$TOOL_NAME.notthistool/jobs/"
    assert_line --partial "403 Forbidden"
}


@test "get builds openapi definition without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/builds/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get builds metrics without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/builds/v1/metrics'"
    assert_success
    assert_line --partial "200 OK"
}


@test "get builds health without auth works" {
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/builds/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}

@test "get builds list for current tool works" {
    run do_curl "$TOOLFORGE_API_URL/builds/v1/tool/$TOOL_NAME/builds"
    assert_line --partial "200 OK"
}

@test "get builds list for other tool fails with forbidden" {
    run do_curl "$TOOLFORGE_API_URL/builds/v1/tool/$TOOL_NAME.notthistool/builds"
    assert_line --partial "403 Forbidden"
}

@test "get components openapi definition without auth works" {
    if [[ "$PROJECT" == "tools" ]]; then
        skip "Skipping components tests"
    fi
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/components/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}

@test "get components health without auth works" {
    if [[ "$PROJECT" == "tools" ]]; then
        skip "Skipping components tests"
    fi
    run bash -c "curl --verbose --insecure '$TOOLFORGE_API_URL/components/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}

teardown() {
    _global_teardown
}
