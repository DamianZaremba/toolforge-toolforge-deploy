#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

RED="\e[41m"
YELLOW="\e[43m"
ENDCOLOR="\e[0m"

TOOLFORGE_DEPLOY_REPO=~/toolforge-deploy
TOOLFORGE_PACKAGE_REGISTRY_DIR=~/.lima-kilo/installed_packages


declare -A NAME_TO_APT_PACKAGE=(
    ["toolforge-weld"]="python3-toolforge-weld"
    ["builds-cli"]="toolforge-builds-cli"
    ["toolforge-cli"]="toolforge-cli"
    ["envvars-cli"]="toolforge-envvars-cli"
    ["jobs-cli"]="toolforge-jobs-framework-cli"
    ["tools-webservice"]="toolforge-webservice"
)


declare -A NAME_TO_HELM_CHART=(
    ["api-gateway"]="api-gateway"
    ["builds-api"]="builds-api"
    ["builds-builder"]="builds-builder"
    ["cert-manager"]="cert-manager"
    ["envvars-admission"]="envvars-admission"
    ["envvars-api"]="envvars-api"
    ["image-config"]="image-config"
    ["jobs-api"]="jobs-api"
    ["kyverno"]="kyverno"
    ["maintain-kubeusers"]="maintain-kubeusers"
    ["registry-admission"]="registry-admission"
    ["volume-admission"]="volume-admission"
    ["wmcs-k8s-metrics"]="wmcs-metrics"
)

ALL_CHARTS_CACHE=""


# helm list -A takes quite a while in tools/toolsbeta, so we cache it
get_all_charts() {
    declare -a extra_opts
    if im_inside_cloudvps; then
        extra_opts=(
            "--kube-as-user=$USER"
            "--kube-as-group=system:masters"
        )
    fi
    if [[ "$ALL_CHARTS_CACHE" == "" ]]; then
        ALL_CHARTS_CACHE=$(helm "${extra_opts[@]}" list -A)
    fi
    echo "$ALL_CHARTS_CACHE"
}


im_inside_cloudvps() {
    [[ -e "/etc/wmcs-project" ]] \
    && grep -q -e '^\(tools\|toolsbeta\)$' "/etc/wmcs-project"
}


get_toolforge_deploy_version() {
    local component="${1?}"
    if [[ "$component" =~ (cert-manager|kyverno) ]]; then
        # it stores the version in the helmfile
        echo "$component-$(grep version "$TOOLFORGE_DEPLOY_REPO"/components/"$component"/helmfile.yaml | awk '{print $2}' | tail -n 1)"
        return 0
    elif [[ "$component" == "wmcs-metrics" ]]; then
        # naming does not match the component name
        echo "wmcs-k8s-metrics-$(grep chartVersion "$TOOLFORGE_DEPLOY_REPO"/components/wmcs-k8s-metrics/values/local.yaml | awk '{print $2}' | tail -n 1)"
        return 0
    fi

    echo "$component-$(grep chartVersion "$TOOLFORGE_DEPLOY_REPO"/components/"$component"/values/local.yaml* | awk '{print $2}')"
    return 0
}


show_package_version() {
    local component="${1?}"
    local package="${NAME_TO_APT_PACKAGE[$component]}"
    local cur_version \
        last_apt_history_entry \
        installed_mr \
        registry_file

    cur_version=$(apt policy "$package" 2>/dev/null| grep '\*\*\*' | awk '{print $2}')
    comment=""
    last_apt_history_entry=$(grep "$package" /var/log/apt/history.log | grep "^Commandline" | tail -n 1 || :)
    registry_file="$TOOLFORGE_PACKAGE_REGISTRY_DIR/$package"
    if [[ "$package" == "toolforge-jobs-framework-cli" ]]; then
        # TODO: get jobs to use the same naming as all the other packages
        registry_file="$TOOLFORGE_PACKAGE_REGISTRY_DIR/toolforge-jobs-cli"
    fi
    if [[ "$last_apt_history_entry" == *_all.deb ]]; then
        installed_mr=$( \
            jq '.mr_number' 2>/dev/null < "$registry_file" \
            || echo "$registry_file" \
        )
        cur_version="$YELLOW$cur_version$ENDCOLOR"
        comment="${YELLOW}mr:$installed_mr$ENDCOLOR"
    fi
    echo -e "| $component | package | $package | $cur_version | $comment |"
}


show_chart_version() {
    local component="${1?}"
    local chart="${NAME_TO_HELM_CHART[$component]}"
    local cur_version
    local td_version
    # warm up the cache
    get_all_charts >/dev/null
    cur_version="$(get_all_charts | grep "^$chart " | awk '{print $9}')"
    comment=""
    td_version=$(get_toolforge_deploy_version "$chart")
    if [[ "$chart" == "wmcs-metrics" ]]; then
        name="wmcs-k8s-metrics"
    else
        name="$chart"
    fi
    if [[ "$cur_version" =~ ^.*-dev-mr-(.*)$ ]]; then
        cur_version="$YELLOW$cur_version$ENDCOLOR"
        comment="${YELLOW}mr:${BASH_REMATCH[1]}$ENDCOLOR"
    elif [[ "$cur_version" != "$td_version" ]]; then
        cur_version="$RED$cur_version$ENDCOLOR"
        comment="${YELLOW}toolforge-deploy has $td_version$ENDCOLOR"
    fi
    echo -e "| $name | chart | $chart | $cur_version | $comment |"
}

main() {
    local component

    # shellcheck disable=SC1078
    for component in "${!NAME_TO_APT_PACKAGE[@]}"; do
        show_package_version "$component"
    done

    # shellcheck disable=SC1078
    for component in "${!NAME_TO_HELM_CHART[@]}"; do
        show_chart_version "$component"
    done
}


echo '| component | type | package name | version | comment |'
echo '| :-------: | :--: | :----------: | :-----: | :-----: |'
main "$@" | sort
