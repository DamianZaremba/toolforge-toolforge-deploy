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


# NOTE: covered by jobs-api tests (tests/runtimes/k8s/test_httproute.py and tests/runtimes/k8s/test_runtime.py::TestCreateContinuousJob), will be deleted
@test "published continuous job fails to run if webservice is already running" {
    toolforge jobs flush

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
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"
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
    assert_line --regexp 'Public:.*yes'
}

@test "restarting a published job preserves ingress access" {
    rand_string="$(cat "$BATS_FILE_TMPDIR/published_job_name")"
    tool_name="${USER#*.}"

    toolforge jobs restart "$rand_string"

    retry "kubectl get deployment '$rand_string' -o jsonpath='{.spec.template.metadata.annotations.app\.kubernetes\.io/restartedAt}' | grep ." 30

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"
}

@test "updating a published job's port keeps external access" {
    rand_string="$(cat "$BATS_FILE_TMPDIR/published_job_name")"
    tool_name="${USER#*.}"

    toolforge jobs dump > "$rand_string.yaml"
    sed -i 's|port: 1234|port: 4321|' "$rand_string.yaml"
    toolforge jobs load "$rand_string.yaml"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"
}


###################################################################
# The scenarios in the tests below are already covered by jobs-api
# unit/integration tests (noted on each test). They are kept here
# temporarily for manual end-to-end verification, and will be deleted.
###################################################################

# NOTE: covered by jobs-api tests (tests/runtimes/k8s/test_jobs.py, PORT env is set from the job's port)
# and by the $PORT check in "published continuous job can be reached by external url", will be deleted
@test "continuous job sets PORT env variable in container" {
    toolforge jobs flush

    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --command "echo \$PORT > port.txt && python3 -m http.server 9999" \
        --port=9999 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100
    retry "test -f \$HOME/port.txt && grep '^9999\$' \$HOME/port.txt" 30
}

# NOTE: covered by jobs-api tests (tests/runtimes/k8s/test_httproute.py), will be deleted
@test "two published continuous jobs in same tool fails with conflict" {
    toolforge jobs flush

    tool_name="${USER#*.}"
    rand_string_a="test-$RANDOM-a"
    rand_string_b="test-$RANDOM-b"

    echo "Creating first published job: $rand_string_a"
    toolforge \
        jobs \
        run \
        --command "python3 -m http.server 8000" \
        --port=8000 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string_a"

    retry "toolforge jobs show '$rand_string_a' | grep 'Status' | grep 'Running'" 100

    echo "Attempting to create second published job: $rand_string_b (should fail)"
    run toolforge \
        jobs \
        run \
        --command "python3 -m http.server 8000" \
        --port=8000 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string_b"
    assert_failure
    assert_line --partial "already in use"
}

# NOTE: covered by jobs-api tests (tests/runtimes/k8s/test_runtime.py TestUpdateContinuousJob), will be deleted
@test "updating a published job to remove publish deletes the HTTPRoute" {
    toolforge jobs flush

    tool_name="${USER#*.}"
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"

    # create published job
    toolforge \
        jobs \
        run \
        --command "python3 -m http.server 8000" \
        --port=8000 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    # verify HTTPRoute exists
    run kubectl get httproute "$rand_string" -o name
    assert_output "httproute.gateway.networking.k8s.io/$rand_string"

    # update to remove publish: dump, remove publish field, load
    toolforge jobs dump > "$rand_string.yaml"
    sed -i '/publish: true/d' "$rand_string.yaml"
    toolforge jobs load "$rand_string.yaml"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    # verify HTTPRoute was deleted but deployment still exists
    run kubectl get httproute "$rand_string" -o name
    assert_failure
    assert_line --partial "not found"

    run kubectl get deployment "$rand_string" -o name
    assert_output "deployment.apps/$rand_string"
}

# NOTE: covered by jobs-api tests (tests/runtimes/k8s/test_runtime.py TestUpdateContinuousJob), will be deleted
@test "updating an unpublished job to add publish creates the HTTPRoute" {
    toolforge jobs flush

    tool_name="${USER#*.}"
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"

    # create unpublished continuous job with a port
    toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 8000" \
        --port=8000 \
        --continuous \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    # verify no HTTPRoute exists yet
    run kubectl get httproute "$rand_string" -o name
    assert_failure
    assert_line --partial "not found"

    # update to add publish: dump, add publish field, load
    toolforge jobs dump > "$rand_string.yaml"
    echo "  publish: true" >> "$rand_string.yaml"
    toolforge jobs load "$rand_string.yaml"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    # verify HTTPRoute now exists
    run kubectl get httproute "$rand_string" -o name
    assert_output "httproute.gateway.networking.k8s.io/$rand_string"
}

# NOTE: covered by jobs-api tests (tests/runtimes/k8s/test_runtime.py TestDeleteJob), will be deleted
@test "deleting a published job cleans up the HTTPRoute" {
    toolforge jobs flush

    tool_name="${USER#*.}"
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"

    toolforge \
        jobs \
        run \
        --command "echo 'OK'>status && python3 -m http.server 8000" \
        --port=8000 \
        --continuous \
        --publish \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    # verify HTTPRoute exists before deletion
    run kubectl get httproute "$rand_string" -o name
    assert_output "httproute.gateway.networking.k8s.io/$rand_string"

    # delete the job
    toolforge jobs delete "$rand_string"

    # verify HTTPRoute was cleaned up
    run kubectl get httproute "$rand_string" -o name
    assert_failure
    assert_line --partial "not found"
}
###################################################################
###################################################################


teardown() {
    _global_teardown
}

teardown_file() {
    toolforge jobs flush
}
