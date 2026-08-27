#!/usr/bin/env bats
# bats file_tags=tools,jobs-api

set -o nounset

setup() {
    load "../../global-common"
    _global_setup

    rm -f test-* check-test-*
    rm -f "service.manifest"
    rm -f "service.template"

    # cleanup webservice just in case
    toolforge webservice stop &>/dev/null || :
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

@test "published continuous job can be reached by external url" {
    toolforge jobs flush

    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    echo "Using job $rand_string"
    # using $PORT also checks that the envvar is set properly in the container
    toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server \${PORT?No port set}" \
        --port=1234 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    # share this job with the following tests, so they don't have to start their own
    echo "$rand_string" > "$BATS_FILE_TMPDIR/published_job_name"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure '$external_url/status' | grep '^OK\$'"
}

@test "published continuous job shows port in show output" {
    rand_string="$(cat "$BATS_FILE_TMPDIR/published_job_name")"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Port:.*1234'
}

@test "published continuous job shows publish status in show output" {
    rand_string="$(cat "$BATS_FILE_TMPDIR/published_job_name")"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Public:.*https?://'
}

@test "restarting a published job preserves ingress access" {
    rand_string="$(cat "$BATS_FILE_TMPDIR/published_job_name")"
    tool_name="${USER#*.}"

    toolforge jobs restart "$rand_string"

    retry "kubectl get deployment '$rand_string' -o jsonpath='{.spec.template.metadata.annotations.app\.kubernetes\.io/restartedAt}' | grep ." 30

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure '$external_url/status' | grep '^OK\$'"
}

@test "updating a published job's port keeps external access" {
    rand_string="$(cat "$BATS_FILE_TMPDIR/published_job_name")"
    tool_name="${USER#*.}"

    toolforge jobs dump > "$rand_string.yaml"
    sed -i 's|port: 1234|port: 4321|' "$rand_string.yaml"
    toolforge jobs load "$rand_string.yaml"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure '$external_url/status' | grep '^OK\$'"
}


teardown() {
    _global_teardown
}

teardown_file() {
    toolforge jobs flush
}
