#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

COMPONENTS=$(ls components)


help() {
    cat <<EOH
    Usage: $0 <COMPONENT> [ENVIRONMENT] [HELMFILE_OPTIONS]

    Deploy the given component your current default k8s cluster (set by the current context in \$KUBECONFIG).

    Arguments:
        COMPONENT
            The toolforge component to deploy, one of: $COMPONENTS

        ENVIRONMENT
            The environment to deploy on, might depend on the component, but usually should be one of:
            * local
            * toolsbeta
            * tools

            Will read it from /etc/wmcs-project if that file is available.

        HELMFILE_OPTIONS
            Any other options that will be passed down to helmfile (ex. --set value)
EOH
}

main() {
    local base_dir \
        deploy_environment \
        component \
        project \
        interactive_param

    if [[ "$1" =~ --?h(elp)? ]]; then
        help
        return 0
    fi

    # explicitly find and specify path to helmfile to allow invoking
    # this script without having to cd to the deployment directory
    base_dir=$(dirname "$(realpath -s "$0")")

    component="${1:?No component passed, choose one of: $COMPONENTS}"
    shift
    if ! [[ -d components/$component ]]; then
        echo "The component '$component' was not found, choose one of: $COMPONENTS"
        help
        return 1
    fi

    cd "$base_dir/components/$component"

    deploy_environment=${1:-}
    project=$(cat /etc/wmcs-project 2>/dev/null || echo "local")

    if [[ "$deploy_environment" == "" ]]; then
        deploy_environment="$project"
    else
        shift
    fi

    valuesfile="values/$deploy_environment.yaml"
    if ! [[ -e  "$valuesfile" ]]; then
        valuesfile="$valuesfile.gotmpl"
        if ! [[ -e  "$valuesfile" ]]; then
            echo "Unable to find values file for the given component/environment combination: ${valuesfile%.gotmpl}/$valuesfile"
            echo "Found values files:"
            ls values/
            exit 1
        fi
    fi
    # use -i (interactive) to ask for confirmation for changing
    # live cluster state if stdin is a tty
    if [[ -t 0 ]]; then
            interactive_param="-i"
    else
            interactive_param=""
    fi

    # helmfile apply will show a diff before doing changes
    helmfile \
        -e "$deploy_environment" \
        --file "helmfile.yaml" \
        $interactive_param \
        apply \
        "$@"
}


main "$@"
