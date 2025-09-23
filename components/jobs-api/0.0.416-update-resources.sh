#!/bin/bash
# shellcheck disable=SC2155

set -o nounset
set -o errexit
set -o pipefail


has_cpu_default_limit() {
    local current_resources="${1?}"
    local current_cpu_limit="$(echo "$current_resources" | jq -r '.limits.cpu')"
    local current_cpu_request="$(echo "$current_resources" | jq -r '.requests.cpu')"

    if [[ "$current_cpu_limit" != "500m" ]] || [[ "$current_cpu_request" != "500m" ]]; then
        echo "    limit: $current_cpu_limit != '500m' || request: $current_cpu_request != '500m'"
        return 1
    fi
    return 0
}


update_cronjob_resources() {
    local namespace="${1?}"
    local cronjob="${2?}"
    local dry_run="${3?}"
    if [[ "$dry_run" == "yes" ]]; then
        cat <<EOC
        Would have run:
    :\$ kubectl -n "$namespace" patch cronjob "$cronjob" --type json -p='[
        {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/limits/cpu", "value":"4000m"},
        {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/requests/cpu", "value":"100m"}
    ]'
EOC
    else
        kubectl -n "$namespace" patch cronjob "$cronjob" --type json -p='[
            {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/limits/cpu", "value":"4000m"},
            {"op": "replace", "path": "/spec/jobTemplate/spec/template/spec/containers/0/resources/requests/cpu", "value":"100m"}
        ]'
    fi
}


update_deployment_resources() {
    local namespace="${1?}"
    local deployment="${2?}"
    local dry_run="${3?}"
    if [[ "$dry_run" == "yes" ]]; then
        cat <<EOC
        Would have run:
        :\$ kubectl -n "$namespace" patch deployment "$deployment" --type json -p='[
            {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value":"4000m"},
            {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value":"100m"}
        ]'
EOC
    else
        kubectl -n "$namespace" patch deployment "$deployment" --type json -p='[
            {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value":"4000m"},
            {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value":"100m"}
        ]'
    fi
}


patch_continuous_jobs() {
    local namespace="${1?}"
    local dry_run="${2?}"
    local resources \
        deployment
    local maybe_deployments="$(kubectl get \
        -n "$namespace" \
        deployments \
        --selector='app.kubernetes.io/component=deployments' \
        --no-headers \
        -o custom-columns=":metadata.name"\
    )"

    if [[ "$maybe_deployments" == "" ]]; then
    echo "  no deployments found for tool $namespace"
        return 0
    fi

    for deployment in $maybe_deployments; do
        echo "  checking deployment $deployment"
        resources="$(kubectl get deployment -n "$namespace" "$deployment" -o json | jq '.spec.template.spec.containers[0].resources')"
        if has_cpu_default_limit "$resources"; then
            echo "    patching deployment $deployment"
            update_deployment_resources "$namespace" "$deployment" "$dry_run"
        else
            echo "    skippping non-default resources deployment $deployment"
        fi
    done
}

patch_scheduled_jobs() {
    local namespace="${1?}"
    local dry_run="${2?}"
    local resources \
        cronjob
    local maybe_cronjobs="$(kubectl get \
        -n "$namespace" \
        cronjobs \
        --selector='app.kubernetes.io/component=cronjobs' \
        --no-headers \
        -o custom-columns=":metadata.name"\
    )"

    if [[ "$maybe_cronjobs" == "" ]]; then
    echo "  no cronjobs found for tool $namespace"
        return 0
    fi

    for cronjob in $maybe_cronjobs; do
        echo "  checking cronjob $cronjob"
        resources="$(kubectl get cronjob -n "$namespace" "$cronjob" -o json | jq '.spec.jobTemplate.spec.template.spec.containers[0].resources')"
        if has_cpu_default_limit "$resources"; then
            echo "    patching cronjob $cronjob"
            update_cronjob_resources "$namespace" "$cronjob" "$dry_run"
        else
            echo "    skippping non-default resources cronjob $cronjob"
        fi
    done
}


main() {
    local namespaces="$(kubectl get ns --no-headers -o custom-columns=":metadata.name" | grep '^tool-')"
    local namespace
    local total_count="$(echo "$namespaces" | wc -l)"
    local cur_count=1
    local dry_run="no"

    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run="yes"
        echo "DRY-RUN"
    fi

    for namespace in $namespaces; do
        echo -e "### Patching tool $namespace... [$cur_count of $total_count]"
        patch_scheduled_jobs "$namespace" "$dry_run"
        patch_continuous_jobs "$namespace" "$dry_run"
        cur_count=$((cur_count+1))
    done
}


main "$@"
