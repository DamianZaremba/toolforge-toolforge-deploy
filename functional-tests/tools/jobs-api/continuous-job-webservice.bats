#!/usr/bin/env bats
# bats file_tags=tools,jobs-api
SAMPLE_REPO_URL=https://gitlab.wikimedia.org/toolforge-repos/sample-static-buildpack-app


set -o nounset

setup_file() {
    load "../../global-common"
    [[ ! -f "$BATS_SKIP_FILE" ]] && toolforge jobs flush
}

setup() {
    load "../../global-common"
    _global_setup

    rm -f test-* check-test-*
    rm -f "service.manifest"
    rm -f "service.template"

    # cleanup webservice just in case
    toolforge webservice stop &>/dev/null || :

    # small webservice web server setup
    APP_DIR="$HOME/www/python/src"
    mkdir -p "$APP_DIR"
    cat > "$APP_DIR/app.py" <<'PYEOF'
def app(environ, start_response):
    start_response('200 OK', [('Content-Type', 'text/plain')])
    return [b'OK']
PYEOF
}


_get_external_url() {
    local tool_name="$1"
    case $PROJECT in
        lima-kilo)
            echo "http://$tool_name.local:30000"
            ;;
        toolsbeta)
            echo "https://$tool_name.beta.toolforge.org"
            ;;
        tools)
            echo "https://$tool_name.toolforge.org"
            ;;
    esac
}


@test "only one webservice job can exist at any point" {
    echo "Using default webservice job name 'webservice'"

    toolforge jobs run --webservice --image=python3.11
    run --separate-stderr toolforge jobs show webservice
    assert_success
    assert_line --regexp 'Job type:.*webservice'

    jobname_b="test-$RANDOM"
    echo "Using job $jobname_b"
    run toolforge jobs run --webservice --image=python3.11 "$jobname_b"
    assert_failure
    assert_line --partial "already in use"
    run toolforge jobs show "$jobname_b"
    assert_failure
    assert_line --partial "Job '$jobname_b' does not exist"
}


@test "webservice job serves traffic and displays resolved defaults" {
    tool_name="${USER#*.}"

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"

    # reuses the existing job
    run --separate-stderr toolforge jobs show webservice
    assert_success
    assert_line --regexp 'Job type:.*webservice'
    assert_line --regexp 'Port:.*8000'
    assert_line --regexp 'Public:.*https?://'

    run --separate-stderr toolforge jobs list
    assert_success
    assert_line --partial "webservice"
}


@test "dumping, loading and updating a webservice job works" {
    # reuses the existing job
    toolforge jobs dump > webservice.yaml
    run grep "name: webservice" webservice.yaml
    assert_success

    sed -i -e '/^  port:/d' -e '/name: webservice/a\  port: 8080' webservice.yaml
    toolforge jobs load webservice.yaml

    run --separate-stderr toolforge jobs show webservice
    assert_success
    assert_line --regexp 'Port:.*8080'

    rm -f webservice.yaml
}


@test "webservice job with custom port is reachable by external url" {
    # reuses the existing job
    tool_name="${USER#*.}"

    run --separate-stderr toolforge jobs show webservice
    assert_success
    assert_line --regexp 'Port:.*8080'

    retry "toolforge jobs show 'webservice' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"

    run --separate-stderr toolforge jobs delete webservice
    assert_success
}

@test "webservice job without command fails with a clear error for images without webservice-defaults" {
    echo "Using default webservice job name 'webservice'"
    run toolforge jobs run --webservice --image=bullseye
    assert_failure
    assert_line --partial "requires that you specify a command"

    run toolforge jobs show webservice
    assert_failure
    assert_line --partial "Job 'webservice' does not exist"
}


@test "run a webservice job with a buildservice image without command uses default web command and port" {
    user="${USER#*.}"

    # we need a build here sadly
    toolforge build start "$SAMPLE_REPO_URL"
    retry "toolforge build show | grep 'Status: ok'"

    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge jobs run --webservice --image="tool-$user/tool-$user:latest" "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Job type:.*webservice'
    assert_line --regexp 'Port:.*8000'
    assert_line --regexp '\| Command: +\| web +\|'

    run --separate-stderr toolforge jobs delete "$rand_string"
    assert_success
}


@test "webservice job with buildservice image uses a custom command as-is" {
    user="${USER#*.}"
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge jobs run --webservice --command "my-custom-web-cmd" --image="tool-$user/tool-$user:latest" "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp '\| Command: +\| my-custom-web-cmd +\|'

    # buildservice commands are used verbatim, not appended to webservice-runner
    refute_line --partial "webservice-runner"
}


teardown() {
    _global_teardown
}

teardown_file() {
    toolforge jobs flush
}
