#!/usr/bin/env bats
# bats file_tags=webservice,service_template,template


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


@test "start webservice from template works" {
    cat >service.template <<EOT
cpu: 500m
mem: 512Mi
# test that the type is not the last, see T379903
type: php8.2
# test that we don't consider extra_args unknown T380141
extra_args: ""
replicas: 1
EOT
    run toolforge webservice start --template=service.template
    assert_success
    assert_line --partial "Starting webservice"

    run toolforge webservice status --template=service.template
    assert_success
    assert_line --partial "webservice of type php8.2 is running"
    refute_line --partial "Your template file (service.template) contains unknown keys"
}


@test "restart" {
    # sometimes we are too fast and the logs are not yet available
    retry "toolforge webservice logs"
    last_line=$(toolforge webservice logs | tail -n 1)
    run toolforge webservice logs
    assert_success
    assert_line "$last_line"

    run toolforge webservice restart
    assert_success
    assert_line --partial "Restarting"

    retry "[[ \"\$(toolforge webservice logs | tail -n 1)\" != '$last_line' ]]"

}

@test "start from template with unknown keys shows warning" {
    # cleanup just in case
    toolforge webservice stop &>/dev/null || :

    cat >service.template <<EOT
cpu: 500m
some_stray_key: something
mem: 512Mi
replicas: 1
type: php8.2
EOT
    run toolforge webservice start --template=service.template
    assert_success
    assert_line --partial "Starting webservice"
    assert_line --partial "Your template file (service.template) contains unknown keys"

    run toolforge webservice status
    assert_success
    assert_line --partial "webservice of type php8.2 is running"
}


@test "start from template that does not contain a dict gives error" {
    # cleanup just in case
    toolforge webservice stop &>/dev/null || :

    cat >service.template <<EOT
- I'm
- an
- array
EOT
    run toolforge webservice start --template=service.template
    assert_failure
}


teardown() {
    _global_teardown
}
