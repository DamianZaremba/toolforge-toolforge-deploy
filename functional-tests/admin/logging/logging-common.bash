LOKI_LOCAL_PORT=13100

_logging_setup() {
    load "../../global-common"
    _global_setup

    if [[ -z "${TEST_TOOL_UID:-}" ]]; then
        echo "env TEST_TOOL_UID is not set and it's required for this test. The value should be the name of the test tool"
        exit 1
    fi

    SUKUBECTL="kubectl --as=$USER --as-group=system:masters"
    if [[ "$PROJECT" == "lima-kilo" ]]; then
        # Local development runs Loki as a single binary, with one service.
        LOKI_INFRASTRUCTURE_READ_SERVICE="loki-infrastructure"
        LOKI_INFRASTRUCTURE_WRITE_SERVICE="loki-infrastructure"
    else
        LOKI_INFRASTRUCTURE_READ_SERVICE="loki-infrastructure-read"
        LOKI_INFRASTRUCTURE_WRITE_SERVICE="loki-infrastructure-write"
    fi
    LOKI_INFRASTRUCTURE_URL="http://127.0.0.1:$LOKI_LOCAL_PORT"
    export SUKUBECTL LOKI_INFRASTRUCTURE_READ_SERVICE LOKI_INFRASTRUCTURE_WRITE_SERVICE LOKI_INFRASTRUCTURE_URL
}

# Forward a local port to the read path of loki-infrastructure.
# The network policies allow only Alloy to connect, and port-forward is not
# affected by them.
_start_loki_infrastructure_port_forward() {
    # Close file descriptor 3, else bats waits for the background process.
    $SUKUBECTL -n loki port-forward "svc/$LOKI_INFRASTRUCTURE_READ_SERVICE" "$LOKI_LOCAL_PORT:3100" >/dev/null 2>&1 3>&- &
    PORT_FORWARD_PID=$!
    retry "curl --silent --output /dev/null '$LOKI_INFRASTRUCTURE_URL/ready'" 30
}

# Print the values of a label in the "infrastructure" tenant.
_loki_infrastructure_label_values_command() {
    local label="${1?}"
    echo "curl --silent --fail --header 'X-Scope-OrgID: infrastructure' '$LOKI_INFRASTRUCTURE_URL/loki/api/v1/label/$label/values' | jq -r '.data[]'"
}

_logging_teardown() {
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
        kill "$PORT_FORWARD_PID" 2>/dev/null || :
        # Wait until the port is free for the next test.
        wait "$PORT_FORWARD_PID" 2>/dev/null || :
    fi
    if [[ -n "${TEST_JOB_NAME:-}" ]]; then
        sudo -i -u "$TEST_TOOL_UID" toolforge jobs delete "$TEST_JOB_NAME" >/dev/null 2>&1 || :
    fi
    _global_teardown
}
