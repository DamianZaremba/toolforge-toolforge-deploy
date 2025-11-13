#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

LOG_FILE="$HOME/tools-migration/tools_migration.log"

exec > >(tee -a "$LOG_FILE") 2>&1

TOOLS_MIGRATION_LIST="$HOME/tools-migration/tools_migration_list.txt"

if [[ ! -f "$TOOLS_MIGRATION_LIST" ]]; then
    echo "Error: $TOOLS_MIGRATION_LIST does not exist."
    exit 1
fi

if [[ ! -f "./util_remove_one_off.py" ]]; then
     echo "Error: file util_remove_one_off.py does not exist on the same dir as this script. It is required."
     exit 1
fi

while IFS= read -r tool_name; do
    if [[ -z "$tool_name" ]]; then
        continue
    fi

    DUMPS_DIR="./tools-migration/dumps/"

    if sudo -i -u "$(cat /etc/wmcs-project).${tool_name}" -- bash -c "
        set -o errexit
        set -o pipefail
        set -o nounset

        mkdir -p \"$DUMPS_DIR\"
        toolforge jobs dump -f \"${DUMPS_DIR}${tool_name}.yaml\"
        ./util_remove_one_off.py \"${DUMPS_DIR}${tool_name}.yaml\"
    "; then
        echo "Successfully dumped jobs for tool_name: $tool_name"
    else
        echo "Failed to dump jobs for tool_name: $tool_name"
    fi
done < "$TOOLS_MIGRATION_LIST"

echo "All operations completed."
