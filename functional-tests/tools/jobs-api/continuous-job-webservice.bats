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
    assert_failure
    assert_line --partial "Job '$rand_string' does not exist"
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


@test "run a webservice job without command" {
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
    assert_line --regexp 'Job type:.*webservice'
}

@test "webservice job can be reached by external url" {
    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"

}


###################################################################
# potentially local lima-kilo only tests. most will be dropped before merging.
# this is only here to make testing by the others easier (and document exactly the things tested)
###################################################################


@test "webservice job creates deployment, service and httproute in the runtime" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o name
    assert_output "deployment.apps/$rand_string"

    run kubectl get service "$rand_string" -o name
    assert_output "service/$rand_string"

    run kubectl get httproute "$rand_string" -o name
    assert_output "httproute.gateway.networking.k8s.io/$rand_string"
}

@test "webservice job shows up in jobs list with the webservice job type" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr toolforge jobs list
    assert_success
    assert_line --regexp "webservice"
    assert_line --partial "$rand_string"
}

@test "jobs show on a webservice job shows the publish url and no user-set port" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Job type:.*webservice'
    assert_line --regexp 'Port:.*N/A'
    assert_line --regexp 'Public:.*https?://'
}

@test "dumping and loading a webservice job keeps it a webservice job" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    toolforge jobs dump > "$rand_string.yaml"
    run grep "webservice: true" "$rand_string.yaml"
    assert_success

    toolforge jobs delete "$rand_string"
    run toolforge jobs show "$rand_string"
    assert_failure
    assert_line --partial "Job '$rand_string' does not exist"

    toolforge jobs load "$rand_string.yaml"

    # the storage record is a webservice one again
    run --separate-stderr toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Job type:.*webservice'
}

@test "updating a webservice job replicas via load updates the deployment" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --replicas=1 \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.replicas}'
    assert_output "1"

    toolforge jobs dump > "$rand_string.yaml"
    sed -i 's|replicas: 1|replicas: 2|' "$rand_string.yaml"
    toolforge jobs load "$rand_string.yaml"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.replicas}'
    assert_output "2"
}

@test "restarting a webservice job keeps it running and reachable" {
    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    run --separate-stderr toolforge jobs restart "$rand_string"
    assert_success

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    external_url="$(_get_external_url "$tool_name")"
    retry "curl --insecure -v '$external_url/status' | grep '^OK\$'"
}

@test "webservice job deployment uses the resolved webservice-runner command" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.template.spec.containers[0]}'
    assert_success
    assert_line --partial "webservice-runner"
}

@test "webservice job with custom command appends it to the webservice-runner command" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --command "custom-extra-arg" \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.template.spec.containers[0]}'
    assert_success
    assert_line --partial "webservice-runner"
    assert_line --partial "custom-extra-arg"
}

@test "webservice job does not create log files, logs go to logs-api" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    # filelog is off for webservices, no log files should exist in the tool home
    run test ! -f "$HOME/$rand_string.out"
    assert_success
    run test ! -f "$HOME/$rand_string.err"
    assert_success

    # logs are served from logs-api instead
    # (retried: loki needs a moment to ingest the pod logs before logs-api can serve them)
    retry "toolforge jobs logs '$rand_string'" 60
}

@test "webservice job sets PORT env variable to the image webservice port in the container" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    retry "toolforge jobs show '$rand_string' | grep 'Status' | grep 'Running'" 100

    retry "kubectl exec 'deploy/$rand_string' -- env | grep '^PORT=8000\$'" 30
}

@test "webservice job with replicas runs the requested amount" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --replicas=2 \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.replicas}'
    assert_output "2"
}

@test "webservice job with memory and cpu sets them on the deployment" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --mem=1Gi \
        --cpu=500m \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'
    assert_output "1Gi"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}'
    assert_output "500m"
}

@test "webservice job with http health check configures the probe on the default port" {
    rand_string="test-$RANDOM"
    echo "Using job $rand_string"
    toolforge \
        jobs \
        run \
        --webservice \
        --health-check-http="/healthz" \
        --mount=all \
        --image=python3.11 \
        "$rand_string"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}'
    assert_output "/healthz"

    run kubectl get deployment "$rand_string" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}'
    assert_output "8000"
}
###################################################################
###################################################################


teardown() {
    _jobs_teardown
    rm -f "$HOME/www/python/src/app.py"
}
