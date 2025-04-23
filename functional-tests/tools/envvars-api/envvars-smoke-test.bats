#!/usr/bin/env bats
# bats file_tags=tools,envvars-api,smoke


set -o nounset

setup() {
    load "../../global-common"
    _global_setup
}


setup_file() {
    # cleanup just in case
    toolforge envvars delete --yes-im-sure TEST_ENVVAR_1 &>/dev/null || :
}


@test "create envvar" {
    toolforge envvars create "TEST_ENVVAR_1" "test-envvar-1-contents"
}


@test "list envvars" {
    run toolforge envvars list --show-values
    assert_line --partial "TEST_ENVVAR_1"
    assert_line --partial "test-envvar-1-contents"
}

@test "list envvars hides envvars values by default" {
    run toolforge envvars list
    assert_line --partial "TEST_ENVVAR_1"
    refute_line --partial "test-envvar-1-contents"
}


@test "show envvars" {
    run toolforge envvars show TEST_ENVVAR_1
    assert_line --partial "TEST_ENVVAR_1"
    assert_line --partial "test-envvar-1-contents"
}


@test "envvars are set inside jobs" {
    toolforge jobs delete test1 &>/dev/null || :
    run toolforge jobs run --wait --image python3.11 --command env test1
    assert_success

    run cat test1.out
    assert_line "TEST_ENVVAR_1=test-envvar-1-contents"
}


@test "delete envvar" {
    run toolforge envvars list
    assert_line --partial "TEST_ENVVAR_1"

    run toolforge envvars delete --yes-im-sure TEST_ENVVAR_1
    assert_line --partial "TEST_ENVVAR_1"
    assert_line --partial "test-envvar-1-contents"


    run toolforge envvars list
    refute_line --partial "TEST_ENVVAR_1"
    refute_line --partial "test-envvar-1-contents"
}


@test "quota" {
    run toolforge envvars quota
    assert_line --partial quota
    assert_line --partial used
    assert_line --partial available
}


teardown() {
    _global_teardown
}
