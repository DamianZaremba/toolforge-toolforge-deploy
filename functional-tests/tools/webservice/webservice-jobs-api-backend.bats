#!/usr/bin/env bats
# bats file_tags=tools,webservice-cli,smoke


set -o nounset

setup() {
    load "../../global-common"
    _global_setup
}


setup_file() {
    # cleanup just in case
    toolforge webservice --backend=jobs-api stop &>/dev/null || :
    rm -f "service.manifest"
    rm -f "service.template"
}


@test "status of stopped jobs-api webservice" {
    run --separate-stderr toolforge webservice --backend=jobs-api status
    assert_success
    assert_line --partial "webservice is not running"
}


@test "start webservice defaults to jobs-api backend" {
    run --separate-stderr toolforge webservice start
    assert_success
    assert_line --partial "Starting webservice"

    run --separate-stderr toolforge webservice status
    assert_success
    assert_line --partial "webservice of type php7.4 is running"

    retry "grep 'backend: jobs-api' '$HOME/service.manifest'" 100
}


@test "get logs of jobs-api webservice" {
    run --separate-stderr retry "toolforge webservice logs"
    assert_success
    assert_line --partial "/usr/sbin/lighttpd"
}


@test "restart jobs-api webservice" {
    last_line=$(toolforge webservice logs | tail -n 1)
    run --separate-stderr toolforge webservice logs
    assert_success
    assert_line "$last_line"

    run --separate-stderr toolforge webservice restart
    assert_success
    assert_line --partial "Restarting"

    retry "[[ \"\$(toolforge webservice logs | tail -n 1)\" != '$last_line' ]]"

}


@test "jobs-api webservice can be reached by external url" {
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


@test "stop jobs-api webservice" {
    run --separate-stderr toolforge webservice stop
    assert_success
    assert_line "Stopping webservice"

    run --separate-stderr toolforge webservice status
    assert_success
    assert_line --partial "webservice is not running"
}


teardown() {
    _global_teardown
}
