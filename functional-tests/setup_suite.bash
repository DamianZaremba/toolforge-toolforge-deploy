# this file runs once per run
# create a link in each subdirectory so it gets loaded also in case you are running only one file

setup_suite() {
    export BATS_SKIP_FILE="$BATS_TMPDIR/$USER.bats.skip"
    # cleanup the skip file on the first run
    rm -f "$BATS_SKIP_FILE"
}


teardown_suite() {
    rm -f "$BATS_SKIP_FILE"
}
