
_jobs_setup() {
    load "../global-common"
    _global_setup

    rm -f test-* check-test-*
    toolforge jobs flush
}

_jobs_teardown() {
    _global_teardown
}
