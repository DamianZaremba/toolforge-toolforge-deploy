#!/bin/bash
# shellcheck disable=SC2209
GITLAB_BASE_URL="https://gitlab.wikimedia.org/repos/cloud/toolforge"

set -o errexit
set -o pipefail
set -o nounset
shopt -s extglob

GREP=grep
if ! grep --version | grep -q 'GNU'; then
    if command -v ggrep; then
        GREP=ggrep
    else
        cat <<EOT
You don't seem to be running GNU grep, some parts if this script might not work.
The easiest workaround is probably for Mac users to just 'brew install grep'
EOT
        exit 1
    fi
fi


cd components
COMPONENTS=(!(helpers))
cd -

help() {
    local components_string=""
    local component
    for component in "${COMPONENTS[@]}" all; do
        components_string+="
                * $component"
    done
    cat <<EOH
    Usage: $0 <COMPONENT>

    Update the given component version if there's a new one.

    Arguments:
        COMPONENT
            The toolforge component to deploy, pass 'all' or one of: $components_string
EOH
}

get_latest_tag() {
    local repo="${1?no component repo passed}"
    local tmpdir

    tmpdir=$(mktemp -d)
    git init "$tmpdir" >/dev/null
    git --git-dir="${tmpdir}/.git" remote add origin "$repo" >/dev/null
    git --git-dir="${tmpdir}/.git" ls-remote --tags origin | awk '{print $2}' | sort -V | tail -n 1 | sed -e 's/refs\/tags\///'
    rm -rf "$tmpdir"
}


update_component() {
    local component="${1?No component passed}" \
        component_repo \
        current_tag \
        latest_tag \
        deployment_files \
        deployment_file \
        deployment

    component_repo="${GITLAB_BASE_URL}/${component}.git"
    latest_tag=$(get_latest_tag "$component_repo")

    if [[ "$latest_tag" == "" ]]; then
        echo "Unable to find a latest release for component $component, maybe it does not have CI setup?"
        return 0
    fi

    some_tag_found="no"
    deployment_files=(components/"$component"/values/*.yaml*)
    for deployment_file in "${deployment_files[@]}"; do
        current_tag=$($GREP -Po '(?<=chartVersion: ).*' "$deployment_file" | sed -e 's/ //g' || echo "tagnotfound")
        if [ "$current_tag" == "tagnotfound" ] ; then
            # this can happen if we have multiple values files, for overrides, but not all of them
            # have the chartVersion entry. See for example wmcs-k8s-metrics
            continue
        fi

        some_tag_found="yes"

        deployment="${deployment_file%%.*}"
        deployment="${deployment##*/}"
        if [[ "$current_tag" != "$latest_tag" ]]; then
            echo "**Updating** $component/$deployment: $current_tag -> $latest_tag"
            sed -i -e "s/chartVersion:.*/chartVersion: $latest_tag/" "$deployment_file"
        else
            echo "Already at latest $component/$deployment: $current_tag == $latest_tag"
        fi
    done

    if [ "$some_tag_found" == "no" ] ; then
        echo "Could not find any chartVersion tag in any deployment value files. Checked: ${deployment_files[*]}"
        exit 1
    fi
}

main() {
    local component \
        component_repo \
        latest_tag

    if [[ "${1:-}" =~ --?h(elp)? ]]; then
        help
        return 0
    fi

    component="${1:?No component passed, pass 'all' or choose one of: ${COMPONENTS[@]}}"
    shift
    if [[ "$component" == "all" ]]; then
        for component in "${COMPONENTS[@]}"; do
            update_component "$component"
        done
    else
        if ! [[ -d components/$component ]]; then
            echo "The component '$component' was not found, choose one of: ${COMPONENTS[*]}"
            help
            return 1
        fi
        update_component "$component"
    fi

    echo -e "\n**NOTE**: you might have to modify helm configuration, this only updates the chart versions."
}



main "$@"
