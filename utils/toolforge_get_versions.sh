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
    ["builds-cli"]="toolforge-builds-cli"
    ["components-cli"]="toolforge-components-cli"
    ["envvars-cli"]="toolforge-envvars-cli"
    ["jobs-cli"]="toolforge-jobs-framework-cli"
    ["toolforge-cli"]="toolforge-cli"
    ["tools-webservice"]="toolforge-webservice"
    ["toolforge-weld"]="python3-toolforge-weld"
)


declare -A NAME_TO_HELM_CHART=(
    ["api-gateway"]="api-gateway"
    ["builds-api"]="builds-api"
    ["builds-builder"]="builds-builder"
    ["calico"]="calico"
    ["cert-manager"]="cert-manager"
    ["components-api"]="components-api"
    ["envvars-admission"]="envvars-admission"
    ["envvars-api"]="envvars-api"
    ["image-config"]="image-config"
    ["ingress-admission"]="ingress-admission"
    ["ingress-nginx"]="ingress-nginx-gen2"
    ["jobs-api"]="jobs-api"
    ["jobs-emailer"]="jobs-emailer"
    ["kyverno"]="kyverno"
    ["maintain-kubeusers"]="maintain-kubeusers"
    ["registry-admission"]="registry-admission"
    ["volume-admission"]="volume-admission"
    ["wmcs-k8s-metrics"]="wmcs-metrics"
    ["maintain-harbor"]="maintain-harbor"
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
    elif [[ "$component" == ingress-nginx-gen2 ]]; then
        # naming does not match the component name
        local dir_name=ingress-nginx
        echo "$dir_name-$(grep chartVersion "$TOOLFORGE_DEPLOY_REPO"/components/"$dir_name"/values/local.yaml | awk '{print $2}' | tail -n 1)"
        return 0
    elif [[ "$component" == wmcs-metrics ]]; then
        # naming does not match the component name
        # additionally, this component contains 4 helm charts
        # FIXME: we are only showing the version of wmcs-metrics, we should show
        # the versions of the other charts as well (tracked in T388382)
        local dir_name=wmcs-k8s-metrics
        echo "$dir_name-$(grep wmcsMetricsChartVersion "$TOOLFORGE_DEPLOY_REPO"/components/"$dir_name"/values/local.yaml | awk '{print $2}' | tail -n 1)"
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
        registry_file \
        comment=""

    # Check if package exists first
    # The output of apt policy will have the installed version starting
    # with three ***, or *** will not be there if it's not installed
    if ! apt policy "$package" 2>/dev/null | grep -q '\*\*\*'; then
        echo -e "| $component | package | $package | ${RED}missing${ENDCOLOR} | |"
        return 0
    fi

    cur_version=$(apt policy "$package" 2>/dev/null | grep '\*\*\*' | awk '{print $2}')
    last_apt_history_entry=$(grep "$package" /var/log/apt/history.log | grep "^Commandline" | tail -n 1 || :)
    registry_file="$TOOLFORGE_PACKAGE_REGISTRY_DIR/$package"
    if [[ "$last_apt_history_entry" == *_all.deb ]]; then
        installed_mr=$( \
            jq '.mr_number' 2>/dev/null < "$registry_file" \
            || echo "$registry_file" \
        )
        cur_version="$YELLOW$cur_version$ENDCOLOR"
        comment="${YELLOW}mr:$component!$installed_mr$ENDCOLOR"
    fi
    echo -e "| $component | package | $package | $cur_version | $comment |"
}


show_chart_version() {
    local component="${1?}"
    local chart="${NAME_TO_HELM_CHART[$component]}"
    local cur_version
    local td_version
    local name
    local comment=""
    # warm up the cache
    get_all_charts >/dev/null

    if [[ "$chart" == "wmcs-metrics" ]]; then
        name="wmcs-k8s-metrics"
    else
        name="$chart"
    fi

    if ! get_all_charts | grep -q "^$chart "; then
        echo -e "| $name | chart | $chart | ${RED}missing${ENDCOLOR} | $comment |"
        return
    fi

    cur_version="$(get_all_charts | grep "^$chart " | awk '{print $9}')"
    td_version=$(get_toolforge_deploy_version "$chart")
    if [[ "$cur_version" =~ ^.*-dev-mr-(.*)$ ]]; then
        cur_version="$YELLOW$cur_version$ENDCOLOR"
        comment="${YELLOW}mr:$component!${BASH_REMATCH[1]}$ENDCOLOR"
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

    if [[ "$USER" != "root" ]] && sudo -n true 2>/dev/null;then # trying to show deployed charts as tool user errors out
        # shellcheck disable=SC1078
        for component in "${!NAME_TO_HELM_CHART[@]}"; do
            show_chart_version "$component"
        done
    fi
}


echo '| component | type | package name | version | comment |'
echo '| :-------: | :--: | :----------: | :-----: | :-----: |'
main "$@" | sort
