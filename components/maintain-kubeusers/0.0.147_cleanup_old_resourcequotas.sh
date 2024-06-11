#!/bin/bash

# Some resourcequotas were created while developing maintain-kubeusers that need cleanup
# as k8s will restrict to the strictest quota.
# The ones that need deleting have the name `<toolname>` while the ones that should be kept have the name `tool-<toolname>` (same as the namespace)

set -e nounset
set -e errexit
set -e pipefail


main() {
    local namespace \
        name \
        ns_name

    while read -r ns_name; do
        name="${ns_name#*:}"
        namespace="${ns_name%:*}"
        echo "Found old resourcequota: $name (ns:$namespace)"
        kubectl \
            --as="$USER" --as-group=system:masters \
            --namespace="$namespace" \
            delete resourcequota "$name"

    done < <(
        kubectl \
            --as="$USER" --as-group=system:masters \
            get resourcequota \
            --all-namespaces \
            --output go-template='{{range .items}}{{if ne .metadata.namespace .metadata.name}}{{printf "%s:%s\n" .metadata.namespace .metadata.name}}{{end}}{{end}}' \
    )
}


main "$@"
