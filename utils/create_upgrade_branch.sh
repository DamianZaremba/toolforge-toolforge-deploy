#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset
shopt -s extglob
GITLAB_REPO_BASE="https://gitlab.wikimedia.org/repos/cloud/toolforge"
GITLAB_RELEASE_SUFFIX="-/releases"

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

    Update the given component version if there's a new one and create a branch with that commit ready to push.

    Note that it will destroy any local changes by resetting to the latest master.

    Arguments:
        COMPONENT
            The toolforge component to upgrade, one of: $components_string
EOH
}

go_to_component_branch_and_reset(){
    local component_branch="${1?No component_branch passed}"
    git fetch --all
    if [[ $(cat .git/HEAD) != "ref: refs/heads/$component_branch" ]]; then
        git checkout -B "bump_$component"
    fi

    git reset --hard origin/main
}


get_bugs_for_upgrade() {
    local repo="${1?no component repo passed}"
    local from_release="${2?no from_release passed}"
    local to_release="${3?no to_release passed}"
    local tmpdir

    tmpdir=$(mktemp -d)
    git init "$tmpdir" >/dev/null
    git --git-dir="${tmpdir}/.git" remote add origin "$repo" >/dev/null
    # TODO: try to fetch only commits between the releases if possible
    git --git-dir="${tmpdir}/.git" fetch origin>/dev/null
    git --git-dir="${tmpdir}/.git" log "$from_release...$to_release" | grep -o "Bug: T[[:digit:]]*"
    rm -rf "$tmpdir"
}

main() {
    local component

    if [[ "${1:-}" =~ --?h(elp)? ]]; then
        help
        return 0
    fi

    component="${1:?No component passed, choose one of: ${COMPONENTS[@]}}"
    shift

    if ! [[ -d components/$component ]]; then
        echo "The component '$component' was not found, choose one of: ${COMPONENTS[*]}"
        help
        return 1
    fi
    go_to_component_branch_and_reset "bump_$component"
    utils/update_component.sh "$component"
    git status | grep -i "changes not staged for commit" || {
        echo "No new versions for component $component"
        return 0
    }

    new_version="$(git diff | grep '+chartVersion' | head -n 1 | awk '{print $2}')"
    prev_version="$(git diff | grep '\-chartVersion' | head -n 1 | awk '{print $2}')"
    git add .
    git commit -s -m "$component: bump to $new_version

From $prev_version
To $new_version
See $GITLAB_REPO_BASE/$component/$GITLAB_RELEASE_SUFFIX

$(get_bugs_for_upgrade "$GITLAB_REPO_BASE/$component" "$prev_version" "$new_version")
"
    echo -e "Branch branch_$component ready to push, if you have the gitlab cli you can:\n"\
        "glab mr create --fill --label 'Needs review' --remove-source-branch --yes\n"\
        "otherwise you can push and manually create the MR."
}



main "$@"
