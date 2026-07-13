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

    APP_DIR="$HOME/www/python/src"
    mkdir -p "$APP_DIR"
    cat > "$APP_DIR/app.py" <<'PYEOF'
def app(environ, start_response):
    start_response('200 OK', [('Content-Type', 'text/plain')])
    return [b'OK']
PYEOF
}


@test "webservice job fails to run if another webservice is already running" {
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
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_failure
    run toolforge jobs show "$rand_string"
    assert_line --regexp "Status:.*Unknown"
}


@test "run a webservice job without command and port defaults to default image cmd and 8000 port" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    run toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"
    assert_success

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Port:.*8000'
}

@test "run a webservice job with a port exposes port internally" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --port=8000 \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Port:.*8000'
}

@test "webservice job can be reached by external url" {
    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --port=8000 \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    case $PROJECT in
        lima-kilo)
            external_url="http://$tool_name.local:30000"
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
    rm -f "$HOME/www/python/src/app.py"
}
