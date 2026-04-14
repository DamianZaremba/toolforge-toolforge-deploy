#!/usr/bin/env bats
# bats file_tags=tools,jobs-api

set -o nounset

setup() {
    load "jobs-common"
    _jobs_setup

    # cleanup webservice just in case
    toolforge webservice stop &>/dev/null || :
    rm -f "service.manifest"
    rm -f "service.template"
}


@test "published continuous job fails to run if webservice is already running" {
    # start webservice
    run --separate-stderr toolforge webservice start
    assert_success
    run --separate-stderr retry "toolforge webservice logs" 100
    assert_success
    assert_line --partial "/usr/sbin/lighttpd"

    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 8000" \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_failure
    run toolforge jobs show "$rand_string"
    assert_line --partial "ERROR"
}


@test "run a published continuous job without port defaults to port 8000" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 8000" \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Port:.*8000'
}

@test "run a published continuous job with a port exposes port" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 1234" \
        --port=1234 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Port:.*1234'
}

@test "published continuous job can be reached by external url" {
    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 1234" \
        --port=1234 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    case $PROJECT in
        lima-kilo)
            external_url="http://$tool_name.local:30002"
            ;;
        toolsbeta)
            external_url="https://$tool_name.beta.toolforge.org"
            ;;
        tools)
            external_url="https://$tool_name.toolforge.org"
            ;;
    esac

    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"

}

teardown() {
    _jobs_teardown
}
