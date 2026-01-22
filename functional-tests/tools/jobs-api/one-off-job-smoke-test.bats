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


@test "run a simple one-off job using prebuilt image web variant" {
    rand_string="test-$RANDOM"
    toolforge \
        jobs \
        run \
        --no-filelog \
        --command "for i in \$(seq 5); do echo 'extraword-$rand_string'; sleep 1; done" \
        --image=toolforge-python39-sssd-web \
        "$rand_string"

    run --separate-stderr retry "toolforge jobs logs \"$rand_string\"" 100
    assert_success
    assert_line --partial "extraword-$rand_string"

    run bash -c "kubectl get job \"$rand_string\" -o json | jq -e '.spec.template.spec.containers[0].image == \"docker-registry.tools.wmflabs.org/toolforge-python39-sssd-base:latest\"'"
    assert_success
}


teardown() {
    _jobs_teardown
}
