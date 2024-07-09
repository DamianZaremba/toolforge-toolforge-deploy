#!/usr/bin/env bats
# bats file_tags=direct-api,smoke


set -o nounset

setup() {
    load "../global-common"
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

get_toolforge_url() {
    grep api_gateway -A 2 /etc/toolforge/common.yaml | grep url: | grep -o 'http.*$'
}


@test "get openapi definition" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars openapi definition without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/envvars/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars metrics without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/envvars/v1/metrics'"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars health without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/envvars/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get envvars list for current tool works" {
    toolforge_url=$(get_toolforge_url)
    run do_curl "$toolforge_url/envvars/v1/tool/$TOOL_NAME/envvar"
    assert_line --partial "200 OK"
}

@test "get envvars list for other tool fails with forbidden" {
    toolforge_url=$(get_toolforge_url)
    run do_curl "$toolforge_url/envvars/v1/tool/$TOOL_NAME.notthistool/envvar"
    assert_line --partial "403 Forbidden"
}

@test "get jobs openapi definition without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/jobs/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get jobs metrics without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/jobs/v1/metrics'"
    assert_success
    assert_line --partial "200 OK"
}


@test "get jobs health without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/jobs/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}

@test "get jobs list for current tool works" {
    toolforge_url=$(get_toolforge_url)
    run do_curl "$toolforge_url/jobs/v1/tool/$TOOL_NAME/jobs/"
    assert_line --partial "200 OK"
}

@test "get jobs list for other tool fails with forbidden" {
    toolforge_url=$(get_toolforge_url)
    run do_curl "$toolforge_url/jobs/v1/tool/$TOOL_NAME.notthistool/jobs/"
    assert_line --partial "403 Forbidden"
}


@test "get builds openapi definition without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/builds/openapi.json' | jq"
    assert_success
    assert_line --partial "200 OK"
}


@test "get builds metrics without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/builds/v1/metrics'"
    assert_success
    assert_line --partial "200 OK"
}


@test "get builds health without auth works" {
    toolforge_url=$(get_toolforge_url)
    run bash -c "curl --verbose --insecure '$toolforge_url/builds/v1/healthz' | jq"
    assert_success
    assert_line --partial "200 OK"
}

@test "get builds list for current tool works" {
    toolforge_url=$(get_toolforge_url)
    run do_curl "$toolforge_url/builds/v1/tool/$TOOL_NAME/build"
    assert_line --partial "200 OK"
}

@test "get builds list for other tool fails with forbidden" {
    toolforge_url=$(get_toolforge_url)
    run do_curl "$toolforge_url/builds/v1/tool/$TOOL_NAME.notthistool/build"
    assert_line --partial "403 Forbidden"
}


teardown() {
    _global_teardown
}
