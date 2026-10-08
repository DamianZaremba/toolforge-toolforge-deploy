_logs_setup() {
    load "../../global-common"
    _global_setup

    rm -f test-* check-test-*
    toolforge jobs flush
}

_logs_teardown() {
    _global_teardown
}
