#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset


LOG_FILE="./tools-migration/tools_migration.log"

exec > >(tee -a "$LOG_FILE") 2>&1

TOOLS_MIGRATION_LIST="./tools-migration/tools_migration_list.txt"

if [[ ! -f "$TOOLS_MIGRATION_LIST" ]]; then
    echo "Error: $TOOLS_MIGRATION_LIST does not exist."
    exit 1
fi

if [[ ! -f "./util_delete_jobs_in_yaml.py" ]]; then
     echo "Error: file util_delete_jobs_in_yaml.py does not exist on the same dir as this script. It is required."
     exit 1
fi

while IFS= read -r tool_name; do
    if [[ -z "$tool_name" ]]; then
        continue
    fi

    DUMPS_DIR="./tools-migration/dumps/"
    file_path="${DUMPS_DIR}${tool_name}.yaml"

    if sudo -i -u "$(cat /etc/wmcs-project).${tool_name}" -- bash -c "
        set -o errexit
        set -o pipefail
        set -o nounset

        if [[ ! -f \"$file_path\" ]]; then
            echo \"Error: \"$file_path\" does not exist.\"
            exit 1
        fi
        ./util_delete_jobs_in_yaml.py \"$(cat /etc/wmcs-project).${tool_name}\" \"$file_path\"
        toolforge jobs load \"$file_path\"
    "; then
        echo "Successfully loaded jobs for tool: $tool_name"
    else
        echo "Failed to load jobs for tool: $tool_name"
    fi
done < "$TOOLS_MIGRATION_LIST"

echo "All operations completed."
