#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail


SECRETS_FILE="${SECRETS_FILE:-/etc/toolforge-deploy/secrets.yaml}"


main() {
    local secret_name
    secret_name="${1:?No secret name passed}"

    if [[ ! -e "$SECRETS_FILE" ]]; then
        echo "Warn: No secrets file found: $SECRETS_FILE" >&2
        return 1
    fi

    python3 -c "
import yaml
secrets=yaml.safe_load(open(\"$SECRETS_FILE\"))
secret_name=\"$secret_name\"
if secret_name not in secrets:
    raise KeyError(f\"Unable to find secret {secret_name}\")
print(secrets[secret_name])
"
    return 0
}

main "$@"
