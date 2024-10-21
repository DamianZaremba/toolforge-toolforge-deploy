_global_setup() {
    export BATS_SKIP_FILE="$BATS_TMPDIR/$USER.bats.skip"
    # this allows not running any tests after the first failure
    [[ ! -f "$BATS_SKIP_FILE" ]] || skip "skip remaining tests ($BATS_SKIP_FILE exists)"

    if ! [[ -e /etc/wmcs-project ]]; then
        echo "This tests are meant to run inside a toolforge environment (/etc/wmcs-project not found)"
        exit 1
    fi

    PROJECT="$(cat /etc/wmcs-project)"
    CLUSTER_DOMAIN="$PROJECT.local"
    if [[ "$PROJECT" == "local" ]]; then
        CLUSTER_DOMAIN="cluster.local"
        PROJECT="lima-kilo"
    fi
    export PROJECT
    export CLUSTER_DOMAIN

    bats_load_library 'bats-support'
    bats_load_library 'bats-assert'
}


_global_teardown() {
    if [[ "${BATS_TEST_COMPLETED}" != "1" ]]; then
        echo "Test failed, creating skip file $BATS_SKIP_FILE"
        touch "$BATS_SKIP_FILE"
        return 1
    fi
}

retry() {
    local command="${1?}"
    # default to 120 because:
    # it seems to be enough for toolsbeta speed
    # it may be enough in case the system needs to download a new container image
    local num_tries="${2:-120}"
    echo "Retrying $num_tries times: $command"
    shift
    for _ in $(seq "$num_tries"); do
        bash -c "$command" && return 0
        sleep 1
    done
    return 1
}
