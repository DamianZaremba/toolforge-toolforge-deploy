#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

LOG_FILE="$HOME/tools-migration/tools_migration.log"
TOOLS_MIGRATION_LIST="$HOME/tools-migration/tools_migration_list.txt"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

if [[ ! -f "$TOOLS_MIGRATION_LIST" ]]; then
    echo "Error: $TOOLS_MIGRATION_LIST does not exist."
    exit 1
fi

while IFS= read -r tool_name; do
    if [[ -z "$tool_name" ]]; then
        continue
    fi

    TOOL_USER="$(cat /etc/wmcs-project).${tool_name}"
    TOOL_HOME=$(getent passwd "$TOOL_USER" | cut -d: -f6)

    if [[ -z "$TOOL_HOME" ]]; then
        echo "Error: Could not find home directory for $TOOL_USER"
        continue
    fi

    TOOL_DUMPS_DIR="$TOOL_HOME/tools-migration/dumps"
    TOOL_FILE_PATH="$TOOL_DUMPS_DIR/$tool_name.yaml"

    if sudo -i -u "$TOOL_USER" -- bash -c "
        set -o errexit;
        set -o pipefail;
        set -o nounset;

        if [[ ! -f \"$TOOL_FILE_PATH\" ]]; then
            echo \"Error: $TOOL_FILE_PATH does not exist.\";
            exit 1;
        fi;

        toolforge jobs load \"$TOOL_FILE_PATH\";

    "; then
        echo "Successfully loaded jobs for tool: $tool_name"
    else
        echo "Failed to load jobs for tool: $tool_name"
    fi
done < "$TOOLS_MIGRATION_LIST"

echo "All operations completed."
