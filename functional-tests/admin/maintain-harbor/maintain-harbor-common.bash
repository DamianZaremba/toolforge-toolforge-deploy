get_harbor_url(){
    local project_name
    project_name=$(cat "/etc/wmcs-project")

    if [[ "$project_name" == "local" ]]; then
        hostname -I | awk '{print $1}'
    else
        echo "${project_name}-harbor.wmcloud.org"
    fi
}

_maintain_harbor_setup() {
    load "../../global-common"
    _global_setup

    if [[ -z "${TEST_TOOL_UID:-}" ]]; then
        echo "env TEST_TOOL_UID is not set and it's required for this test. The value should be the name of the test tool"
        exit 1
    fi

    SAMPLE_REPO_URL=https://gitlab.wikimedia.org/toolforge-repos/sample-static-buildpack-app
    HARBOR_URL="$(get_harbor_url)/api/v2.0"
    HARBOR_PROJECT_NAME="tool-$(echo "$TEST_TOOL_UID" | awk -F '.' '{print $2}')"
    SUKUBECTL="kubectl --as=$USER --as-group=system:masters -n maintain-harbor"
    HARBOR_USERNAME=$(
        $SUKUBECTL get secret maintain-harbor-secret -o yaml \
        | grep "MAINTAIN_HARBOR_AUTH_USERNAME:" | awk '{print $2}' | base64 --decode)
    HARBOR_PASSWORD=$(
        $SUKUBECTL get secret maintain-harbor-secret -o yaml \
        | grep "MAINTAIN_HARBOR_AUTH_PASSWORD:" | awk '{print $2}' | base64 --decode)
    CURL="curl -u $HARBOR_USERNAME:$HARBOR_PASSWORD -H Content-Type:application/json -k"
    CURL_VERBOSE="curl --verbose -u $HARBOR_USERNAME:$HARBOR_PASSWORD -H Content-Type:application/json -ki"

    export SAMPLE_REPO_URL HARBOR_URL HARBOR_PROJECT_NAME HARBOR_USERNAME HARBOR_PASSWORD SUKUBECTL CURL CURL_VERBOSE
}

_maintain_harbor_teardown() {
    _global_teardown
}
