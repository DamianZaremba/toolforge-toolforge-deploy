#!/usr/bin/env bats
# bats file_tags=tools,jobs-api,smoke

set -o nounset


setup() {
    load "jobs-common"
    _jobs_setup
}


@test "run a simple one-off job with filelog, and check the logs" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --filelog \
        --wait 120 \
        --command "echo '$rand_string'" \
        --image=python3.11 \
        "$rand_string"

    retry "grep '$rand_string' '$HOME/$rand_string.out'" 100
}


@test "run a simple one-off job without filelog, and check the logs" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo 'extraword-$rand_string'; sleep 1; done" \
        --image=python3.11 \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"
}


@test "run a simple one-off job using prebuilt image alias" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo 'extraword-$rand_string'; sleep 1; done" \
        --image=tf-python39 \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"
}


@test "run a simple one-off job using prebuilt image full url" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo 'extraword-$rand_string'; sleep 1; done" \
        --image=docker-registry.tools.wmflabs.org/toolforge-python39-sssd-web:latest \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"
}


@test "run a simple one-off job using prebuilt image base variant" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo 'extraword-$rand_string'; sleep 1; done" \
        --image=docker-registry.tools.wmflabs.org/toolforge-python39-sssd-base:latest \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"

    run bash -c "kubectl get job \"$rand_string\" -o json | jq -e '.spec.template.spec.containers[0].image == \"docker-registry.tools.wmflabs.org/toolforge-python39-sssd-web:latest\"'"
    assert_success
}


@test "run a simple one-off job using just prebuilt image name, without adding variant string" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo 'extraword-$rand_string'; sleep 1; done" \
        --image=toolforge-python39 \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"

    run bash -c "kubectl get job \"$rand_string\" -o json | jq -e '.spec.template.spec.containers[0].image == \"docker-registry.tools.wmflabs.org/toolforge-python39-sssd-web:latest\"'"
    assert_success
}


@test "simple one-off k8s job using web image variant get parsed correctly" {
    rand_string="test-$RANDOM"
    tool_name="${USER#*.}"
    web_image_variant="docker-registry.tools.wmflabs.org/toolforge-python39-sssd-base:latest"

    run --separate-stderr kubectl create -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $rand_string
  labels:
    app.kubernetes.io/component: jobs
    app.kubernetes.io/created-by: $tool_name
    app.kubernetes.io/managed-by: toolforge-jobs-framework
    app.kubernetes.io/name: $rand_string
    app.kubernetes.io/version: "2"
    jobs.toolforge.org/emails: none
    jobs.toolforge.org/filelog: "yes"
    toolforge.org/mount-storage: all
    toolforge: tool
spec:
  ttlSecondsAfterFinished: 30
  backoffLimit: 5
  template:
    metadata:
      labels:
        app.kubernetes.io/component: jobs
        app.kubernetes.io/created-by: $tool_name
        app.kubernetes.io/managed-by: toolforge-jobs-framework
        app.kubernetes.io/name: $rand_string
        app.kubernetes.io/version: "2"
        jobs.toolforge.org/emails: none
        jobs.toolforge.org/filelog: "yes"
        toolforge.org/mount-storage: all
        batch.kubernetes.io/job-name: $rand_string
        job-name: $rand_string
        toolforge: tool
    spec:
      restartPolicy: Never
      terminationGracePeriodSeconds: 15
      containers:
        - name: job
          image: $web_image_variant
          workingDir: /data/project/$tool_name
          command:
            - /bin/sh
            - -c
            - --
            - exec 1>>/data/project/$tool_name/$rand_string.out;exec 2>>/data/project/$tool_name/$rand_string.err;for i in \$(seq 5);do echo 'extraword-$rand_string';sleep 1;done
EOF
    assert_success

    run toolforge jobs show "$rand_string"
    assert_success
    assert_line --regexp 'Image: *| python3.9'
}


teardown() {
    _jobs_teardown
}
