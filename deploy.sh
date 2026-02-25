#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset
shopt -s extglob

BASE_DIR=$(dirname "$(realpath -s "$0")")


cd "$BASE_DIR/components"
COMPONENTS=(!(helpers|common))
cd -


help() {
    local components_string=""
    local component
    for component in "${COMPONENTS[@]}"; do
        components_string+="
                * $component"
    done
    cat <<EOH
    Usage: $0 <COMPONENT> [ENVIRONMENT] [HELMFILE_OPTIONS]

    Deploy the given component your current default k8s cluster (set by the current context in \$KUBECONFIG).

    Arguments:
        COMPONENT
            The toolforge component to deploy, one of: $components_string

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
    local deploy_environment \
        component \
        project \
        interactive_param

    if [[  "$1" =~ ^-h$|^--help$ ]]; then
        help
        return 0
    fi

    component="${1:?No component passed, choose one of: ${COMPONENTS[@]}}"
    shift
    if ! [[ -d $BASE_DIR/components/$component ]]; then
        echo "The component '$component' was not found, choose one of: ${COMPONENTS[*]}"
        help
        return 1
    fi

    # explicitly find and specify path to helmfile to allow invoking
    # this script without having to cd to the deployment directory
    cd "$BASE_DIR/components/$component"

    # give components the ability to override the deployment process from
    # the standard helmfile. this is needed at least for Gateway API CRDs
    # which are not distributed as a Helm chart
    if [[ -e "override-deploy.sh" ]]; then
        exec ./override-deploy.sh
        exit 0
    fi

    project=$(cat /etc/wmcs-project 2>/dev/null || echo "local")
    # If we got any flags, no env was passed, ex. --wait
    if [[ "${1:-}" != --* ]]; then
        deploy_environment=${1:-}
    else
        deploy_environment=""
    fi

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

    # We use "helmfile diff" + "helmfile sync", instead of "helmfile apply",
    # because apply will not update the installed version if the diff is empty.
    helmfile \
        -e "$deploy_environment" \
        --file "helmfile.yaml" \
        diff \
        "${@/--wait/}" # ugly hack because --wait is not valid for "helmfile diff"
    helmfile \
        -e "$deploy_environment" \
        --file "helmfile.yaml" \
        $interactive_param \
        sync \
        "$@"
}


main "$@"
