#!/bin/bash

# The name of the configmap used for maintain-kubeusers changed with the last refactor
# and the old one is not needed anymore, the new name is maintain-kubeusers-<toolname>

set -e nounset
set -e errexit
set -e pipefail


main() {
    local namespace

    while read -r namespace; do
        echo "Found old configmap maintain-kubeusers in tool namespace $namespace"
        kubectl \
            --as="$USER" --as-group=system:masters \
            --namespace="$namespace" \
            delete configmap maintain-kubeusers

    done < <(
        kubectl \
            --as="$USER" --as-group=system:masters \
            get configmap \
            --all-namespaces \
            --field-selector 'metadata.name=maintain-kubeusers,metadata.namespace!=maintain-kubeusers' \
            --output go-template='{{range .items}}{{printf "%s\n" .metadata.namespace}}{{end}}' \
    )
}


main "$@"
