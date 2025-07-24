# shellcheck disable=SC2155
# this file runs once per run
# create a link in each subdirectory so it gets loaded also in case you are running only one file

setup_suite() {
    export BATS_SKIP_FILE="$BATS_TMPDIR/$USER.bats.skip"
    # cleanup the skip file on the first run
    rm -f "$BATS_SKIP_FILE"
    export TOOLFORGE_API_URL=$(grep api_gateway -A 2 /etc/toolforge/common.yaml | grep url: | grep -o 'http.*$')
    bats_require_minimum_version 1.5.0
}


teardown_suite() {
    rm -f "$BATS_SKIP_FILE"
}
