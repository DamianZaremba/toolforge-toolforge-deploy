#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

LOG_FILE="$HOME/tools-migration/tools_migration.log"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

OUTPUT_FILE="$HOME/tools-migration/tools_migration_list.txt"

mkdir -p "$(dirname "$OUTPUT_FILE")"

CRONJOBS=$(kubectl get cronjobs -A -l app.kubernetes.io/managed-by=toolforge-jobs-framework,app.kubernetes.io/version=1,app.kubernetes.io/component=cronjobs -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}')
DEPLOYMENTS=$(kubectl get deployments -A -l app.kubernetes.io/managed-by=toolforge-jobs-framework,app.kubernetes.io/version=1,app.kubernetes.io/component=deployments -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}')

TOOLS=$(echo -e "${CRONJOBS}\n${DEPLOYMENTS}" | sed 's/^tool-//' | sed '/^$/d' | sort | uniq)

echo "$TOOLS" > "$OUTPUT_FILE"

echo "names of tools that require migration has been written to $OUTPUT_FILE"
