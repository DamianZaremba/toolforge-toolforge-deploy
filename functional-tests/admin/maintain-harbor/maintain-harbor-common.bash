get_harbor_url(){
    local project_name
    project_name=$(cat "/etc/wmcs-project")

    if [[ "$project_name" == "local" ]]; then
        echo "http://$(hostname -I | awk '{print $1}')"
    else
        echo "https://${project_name}-harbor.wmcloud.org"
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
    HARBOR_CONFIGMAP=$($SUKUBECTL get configmap maintain-harbor-config -o json)
    CURL="curl --netrc -H Content-Type:application/json -k"
    CURL_VERBOSE="curl --netrc --verbose -H Content-Type:application/json --insecure --include"
    CURL_VERBOSE_FAIL_WITH_BODY="curl --netrc --verbose --fail-with-body -H Content-Type:application/json --insecure --include"

    export SAMPLE_REPO_URL HARBOR_URL HARBOR_PROJECT_NAME SUKUBECTL CURL CURL_VERBOSE CURL_VERBOSE_FAIL_WITH_BODY HARBOR_CONFIGMAP

    # Create .netrc file for curl authentication
    touch ~/.netrc
    # Set correct permissions for .netrc to avoid security warnings
    chmod 600 ~/.netrc
    cat <<EOF > ~/.netrc
machine $(get_harbor_url | awk -F '//' '{print $2}')
login $HARBOR_USERNAME
password $HARBOR_PASSWORD
EOF
}

_maintain_harbor_teardown() {
    rm -rf ~/.netrc
    _global_teardown
}
