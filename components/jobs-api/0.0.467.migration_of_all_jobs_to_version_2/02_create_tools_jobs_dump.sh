#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

LOG_FILE="$HOME/tools-migration/tools_migration.log"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TOOLS_MIGRATION_LIST="${1:-$HOME/tools-migration/tools_migration_list.txt}"
SOURCE_REMOVE_ONE_OFF_SCRIPT="${SCRIPT_DIR}/util_remove_one_off.py"
REMOVE_ONE_OFF_SCRIPT="/tmp/util_remove_one_off.py"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

if [[ ! -f "$TOOLS_MIGRATION_LIST" ]]; then
    echo "Error: $TOOLS_MIGRATION_LIST does not exist."
    exit 1
fi

if [[ ! -f "$SOURCE_REMOVE_ONE_OFF_SCRIPT" ]]; then
     echo "Error: $SOURCE_REMOVE_ONE_OFF_SCRIPT does not exist."
     exit 1
fi

# make it accessible to tools
cp "$SOURCE_REMOVE_ONE_OFF_SCRIPT" "$REMOVE_ONE_OFF_SCRIPT"


PROJECT="$(cat /etc/wmcs-project)"

while IFS= read -r tool_name; do
    if [[ -z "$tool_name" ]]; then
        continue
    fi

    TOOL_USER="$PROJECT.${tool_name}"

    TOOL_HOME=$(getent passwd "$TOOL_USER" | cut -d: -f6)

    if [[ -z "$TOOL_HOME" ]]; then
        echo "Error: Could not find home directory for $TOOL_USER"
        continue
    fi

    TOOL_DUMPS_DIR="$TOOL_HOME/.tools-migration/dumps"
    TOOL_OUTPUT_FILE="$TOOL_DUMPS_DIR/$tool_name.yaml"

    if sudo -i -u "$TOOL_USER" -- bash -c "
        set -o errexit;
        set -o pipefail;
        set -o nounset;

        mkdir -p \"$TOOL_DUMPS_DIR\";

        toolforge jobs dump -f \"$TOOL_OUTPUT_FILE\";
        echo \"Successfully dumped $tool_name jobs to $TOOL_OUTPUT_FILE\";

        \"$REMOVE_ONE_OFF_SCRIPT\" \"$TOOL_OUTPUT_FILE\";

    "; then
        echo "Successfully dumped jobs for tool_name: $tool_name"
    else
        echo "Failed to dump jobs for tool_name: $tool_name"
    fi
done < "$TOOLS_MIGRATION_LIST"

echo "All operations completed."
