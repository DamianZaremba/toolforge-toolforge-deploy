#!/usr/bin/env bats
# bats file_tags=tools,webservice,smoke


set -o nounset

setup() {
    load "../../global-common"
    _global_setup
}


setup_file() {
    # cleanup just in case
    toolforge webservice stop &>/dev/null || :
    rm -f "service.manifest"
    rm -f "service.template"
}


@test "status of stopped webservice" {
    run toolforge webservice status
    assert_success
    assert_line --partial "webservice is not running"
}


@test "start webservice" {
    run toolforge webservice start
    assert_success
    assert_line --partial "Starting webservice"

    run toolforge webservice status
    assert_success
    assert_line --partial "webservice of type php7.4 is running"
}


@test "get logs" {
    run retry "toolforge webservice logs"
    assert_success
    assert_line --partial "/usr/sbin/lighttpd"
}


@test "restart" {
    last_line=$(toolforge webservice logs | tail -n 1)
    run toolforge webservice logs
    assert_success
    assert_line "$last_line"

    run toolforge webservice restart
    assert_success
    assert_line --partial "Restarting"

    retry "[[ \"\$(toolforge webservice logs | tail -n 1)\" != '$last_line' ]]"

}


@test "can be reached by external url" {
    tool="${USER#*.}"

    case $PROJECT in
        lima-kilo)
            external_url="http://$tool.local:30002"
            ;;
        toolsbeta)
            external_url="https://$tool.beta.toolforge.org"
            ;;
        tools)
            external_url="https://$tool.toolforge.org"
            ;;
    esac

    mkdir -p public_html
    echo "OK" > public_html/healthz
    retry "curl --insecure -v '$external_url/healthz' | grep '^OK\$'"
}


@test "stop" {
    run toolforge webservice stop
    assert_success
    assert_line "Stopping webservice"

    run toolforge webservice status
    assert_success
    assert_line --partial "webservice is not running"
}


@test "shell starts and echoes" {
    random_token="$RANDOM-token"
    run bash -c "toolforge webservice php7.4 shell -- echo '$random_token'"
    assert_success
    assert_line --partial "$random_token"
}


teardown() {
    _global_teardown
}
