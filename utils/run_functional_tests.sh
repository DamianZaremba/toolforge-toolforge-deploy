#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

TOOLFORGE_DEPLOY_URL="https://gitlab.wikimedia.org/repos/cloud/toolforge/toolforge-deploy"
declare -A DEFAULT_TEST_TOOLS_PER_ENV
DEFAULT_TEST_TOOLS_PER_ENV["local"]="tf-test"
DEFAULT_TEST_TOOLS_PER_ENV["toolsbeta"]="test"
DEFAULT_TEST_TOOLS_PER_ENV["tools"]="automated-toolforge-tests"
SOURCE_FILE_NAME="functional-tests-source-file-$RANDOM"


help() {
    cat <<EOH
        Usage:
            $0 [options] -- [extra-args]

        Options:
            -h|--help
                Show this help

            -r|--refetch-tests
                If passed, it will make sure the tests are in the latest version
                by fetching the latest commit from the toolforge deploy repo:
                ($TOOLFORGE_DEPLOY_URL)

            -b|--branch
                toolforge-deploy branch to use for the test. defaults to main

            -t|--test-tool
                Name of the tool to use for the testing without prefix (ex. tf-test or wm-lol)

            -c|--component
                This is used to determine the test tags to use (ex. -c builds-api -c jobs-api)

            -v|--verbose
                If passed, it will use extra verbose options to show extra logs.

        Arguments:
            extra-args
                If passed, it will be passed as-is to bats as extra arguments.
                Usefule for example to filter tests to run, for example:
                    For more control over the tests that run, use --filter to filter by test name:
                    * --filter '.*continuous job.*'

                    For more control over the tests that run, use --filter-tags to filter by tag:
                    * --filter-tags jobs-api


        Example:
            To run in toolforge deployment using the wm-lol tool as test tool and fetching the latest test:

            toolforge> $0 --refetch-tests --test-tool wm-lol

EOH
}

run_as_user() {
    local user="$1"
    shift
    sudo -i -u "$user" bash -c "$@" || {
        local err=$?
        if [[ $err -eq 1 ]]; then
            # if permission error user is likey already a tool, retry directly without sudo
            bash -c "$@"
        else
            return $err
        fi
    }
}

remove_file() {
    local userhome
    local user="${1?}"
    local filename="${2?}"
    userhome="$(eval echo ~"$user")"
    local file="$userhome/$filename"
    run_as_user "$user" "rm -f \"$file\""
}

ensure_lock() {
    local userhome
    local user="${1?}"
    userhome="$(eval echo ~"$user")"
    local lockfile="$userhome/functional_tests.lock"
    local pid="$$"
    if ! [[ -e "$lockfile" ]]; then
        run_as_user "$user" "echo \"$pid\" > \"$lockfile\""
        return 0
    fi

    pid="$(cat "$lockfile")"
    if [[ "$(pgrep --pidfile "$lockfile")" == "" ]]; then
        echo "Found stale lockfile $lockfile (pid $pid), removing and continuing..."
        return 0
    fi

    echo "Found already running tests (lockfile $lockfile, pid $pid), can't run in parallel, aborting"
    return 1
}

inside_toolforge_deployment() {
    if [[ -e /etc/wmcs-project ]]; then
        grep -q 'tools' /etc/wmcs-project
        return $?
    fi
    return 1
}

inside_lima_kilo() {
    if [[ -e /etc/wmcs-project ]]; then
        grep -q 'local' /etc/wmcs-project
        return $?
    fi
    return 1
}

is_login_user() {
    if [[ "$USER" != "root" ]] && sudo -n true 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

is_tool_user() {
    local test_tool_uid="${1?}"
    if [[ "$USER" == "$test_tool_uid" ]]; then
        return 0
    else
        return 1
    fi
}

setup_venv() {
    if ! [[ -e "$HOME/venv/bin/activate" ]]; then
        if inside_toolforge_deployment; then
            # shellcheck disable=SC2016
            # double -- as the `toolforge` cli swallows it (T370184)
            toolforge webservice python3.11 shell -- -- bash -c 'python3 -m venv "$TOOL_DATA_DIR/venv"'
            local retries=10
            while ! [[ -e "$HOME/venv/bin/activate" ]]; do
                echo "Waiting for nfs to sync up..."
                # Force NFS to re-check the home dir
                ls "$HOME" &>/dev/null || :
                sleep 1
                retries=$((retries - 1))
                if [[ "$retries" -le 0 ]]; then
                    echo "ERROR: Unable to find the venv created with webservice" >&2
                    return 1
                fi
            done
        else
            # TODO: use webservice for lima-kilo once it's supported there
            python3 -m venv "$HOME/venv"
        fi
    fi
    # shellcheck disable=SC1091
    source "$HOME/venv/bin/activate"

    command -v bats_core_pkg >/dev/null \
    || pip install --upgrade bats-core-pkg
}

setup_toolforge_deploy() {
    local refetch="${1?}"
    local branch="${2?}"
    echo "@@@@@@@@ Configuring toolforge-deploy for $USER"
    if ! [[ -e "$HOME"/toolforge-deploy ]]; then
        git clone "$TOOLFORGE_DEPLOY_URL" "$HOME"/toolforge-deploy
    fi

    cd "$HOME"/toolforge-deploy
    git fetch --all 2>/dev/null
    if ! git branch -a | grep -qwE "$branch|remotes/origin/$branch"; then
        echo "Branch \"$branch\" not found in \"$HOME/toolforge-deploy\" or \"$TOOLFORGE_DEPLOY_URL\". Defaulting to \"main\""
        branch="main"
    fi

    git switch --track origin/"$branch" 2>/dev/null || git switch "$branch"
    if [[ "$refetch" == "yes" ]]; then
        git reset --hard origin/"$branch"
    fi

    cd -
    echo "@@@@@@@@ Configured toolforge-deploy for $USER. Branch: $(git -C "$HOME"/toolforge-deploy branch | grep '^\*')"
}

get_component_test_tags() {
    local component="$1"
    local test_tool_home="$2"
    local -a test_tags

    component_dir="${test_tool_home}/toolforge-deploy/components/${component}"
    test_file="${component_dir}/tests.txt"

    if [[ ! -f "${test_file}" ]]; then
        return 0
    fi

    while IFS= read -r test_tag; do
        test_tags+=(--filter-tags "$test_tag")
    done < <(grep '^[^#]' "$test_file")

    if [[ ${#test_tags[@]} -gt 0 ]]; then
        printf '%s\n' "${test_tags[@]}"
    fi
}

run_tests() {
    local components_str="${1?}"  # Comma-separated components str or "all"
    local test_tool_home="${2?}"
    local dir="${3?}"
    shift 3

    local -a extra_args=("$@")

    # check if caller already provided --filter-tags
    local has_filter_tags="no"
    for arg in "${extra_args[@]}"; do
        if [[ "$arg" == "--filter-tags" ]]; then
            has_filter_tags="yes"
            break
        fi
    done

    # Split component_str into array
    local -a components
    if [[ "$components_str" != "all" ]]; then
        IFS=, read -ra components <<< "$components_str"
    fi

    if [[ "$components_str" != "all" && "$has_filter_tags" == "no" ]]; then
        for component in "${components[@]}"; do
            mapfile -t test_tags < <(get_component_test_tags "$component" "$test_tool_home")
            if [[ ${#test_tags[@]} -gt 0 ]]; then
                extra_args+=("${test_tags[@]}")
            fi
        done
    fi

    # we need to be in the home of the tool, where the jobs will create the logs
    cd "$test_tool_home"
    cat <<EOM
## Command run for easy copy-paste
source "$test_tool_home/venv/bin/activate" && bats_core_pkg \\
    --verbose-run \\
    --pretty \\
    --timing \\
    --recursive \\
    --setup-suite-file "${test_tool_home}/toolforge-deploy/functional-tests/setup_suite.bash" \\
    "${test_tool_home}/toolforge-deploy/functional-tests/${dir}" \\
    "${extra_args[@]}"
EOM
    # shellcheck disable=SC1091
    source "$test_tool_home/venv/bin/activate" && bats_core_pkg \
        --verbose-run \
        --pretty \
        --timing \
        --recursive \
        --setup-suite-file "${test_tool_home}/toolforge-deploy/functional-tests/setup_suite.bash" \
        "${test_tool_home}/toolforge-deploy/functional-tests/${dir}" \
        "${extra_args[@]}"
}


main() {
    local refetch="no"
    local verbose="no"
    local git_branch="main"
    local -a components=()
    local opts \
        test_tool_uid \
        current_project \
        test_tool_name=""


    opts=$(getopt -o 'hrvt:b:c:' --long 'help,verbose,refetch-tests,test-tool:,branch:,component:' -n "$0" -- "$@")
    # shellcheck disable=SC2181
    if [[ $? -ne 0 ]]; then
        echo 'Wrong options' >&2
        help
        exit 1
    fi

    eval set -- "$opts"
    unset opts

    while true; do
        case "$1" in
            '-h'|'--help')
                help
                exit
            ;;
            '-v'|'--verbose')
                verbose="yes"
                shift
                set -x
                continue
            ;;
            '-r'|'--refetch-tests')
                refetch="yes"
                shift
                continue
            ;;
            '-t'|'--test-tool')
                test_tool_name="$2"
                shift 2
                continue
            ;;
            '-b'|'--branch')
                git_branch="$2"
                shift 2
                continue
            ;;
            '-c'|'--component')
                components+=("$2")
                shift 2
                continue
            ;;
            '--')
                shift
                break
            ;;
            *)
                echo "Wrong option: $1" >&2
                help
                exit 1
            ;;
        esac
    done

    local verbose_options=(
        "--print-output-on-failure"
    )
    if [[ "$verbose" == "yes" ]]; then
        verbose_options=(
            "--show-output-of-passing-tests"
            "--trace"
        )
    fi

    if [[ ! -e "/etc/wmcs-project" ]]; then
        echo "This script is meant to run inside a toolforge environment (/etc/wmcs-project not found)"
        exit 1
    fi

    current_project="$(cat /etc/wmcs-project)"
    if [[ "$test_tool_name" == "" ]]; then
        if [[ "${DEFAULT_TEST_TOOLS_PER_ENV[$current_project]}" == "" ]]; then
            echo "Unable to guess a tool to use for environment $current_project, you can pass one with -t"
            exit 1
        fi
        test_tool_uid="$current_project.${DEFAULT_TEST_TOOLS_PER_ENV[$current_project]}"
    else
        test_tool_uid="$current_project.$test_tool_name"
    fi

    if ! id -u "$test_tool_uid" &>/dev/null; then
        echo "Unable to find user for tool $test_tool_name (uid:$test_tool_uid). If running in tools/toolsbeta, you should specify one with -t"
        exit 1
    fi

    if ! is_login_user && ! is_tool_user "$test_tool_uid" ; then
        echo "You can only run tests either as $test_tool_uid or as a login user"
        echo "If you want to run tests as a different tool, become the tool then run the script again with --test-tool <tool-name>"
        exit 1
    fi

    # since tests are no longer always run as tool user, we can't depend on $USER
    export TEST_TOOL_UID="$test_tool_uid"

    ensure_lock "$TEST_TOOL_UID"
    trap 'remove_file "$TEST_TOOL_UID" "functional_tests.lock"; remove_file "$TEST_TOOL_UID" "$SOURCE_FILE_NAME"' EXIT

    if is_login_user; then
        echo "Installed toolforge components and CLIs versions:"
        # 47 chars. Note that this is being used here https://gerrit.wikimedia.org/r/plugins/gitiles/cloud/wmcs-cookbooks/+/refs/heads/main/cookbooks/wmcs/toolforge/component/deploy.py#222
        echo "-----------------------------------------------"
        "${0%/*}"/toolforge_get_versions.sh
         # 47 chars. Note that this is being used here https://gerrit.wikimedia.org/r/plugins/gitiles/cloud/wmcs-cookbooks/+/refs/heads/main/cookbooks/wmcs/toolforge/component/deploy.py#222
        echo "-----------------------------------------------"
        echo -e "\n"

        local test_tool_home
        test_tool_home="$(sudo -i -u "$TEST_TOOL_UID" bash -c "echo \"\$HOME\"")"
        sudo cp "$(realpath "$0")" "$test_tool_home/$SOURCE_FILE_NAME"

        sudo -i -u "$TEST_TOOL_UID" bash -c "source $test_tool_home/$SOURCE_FILE_NAME && setup_venv"
        setup_toolforge_deploy "$refetch" "$git_branch"
        sudo -i -u "$TEST_TOOL_UID" bash -c "source $test_tool_home/$SOURCE_FILE_NAME && setup_toolforge_deploy \"\$@\"" -- "$refetch" "$git_branch"

        local components_str="all"
        if [[ ${#components[@]} -gt 0 ]]; then
            for component in "${components[@]}"; do
                local component_dir="${test_tool_home}/toolforge-deploy/components/$component"
                if [[ ! -d "$component_dir" ]]; then
                    echo "The component ${component} doesn't exist. Exiting..."
                    exit 1
                fi
            done
            # create comma separated components string
            components_str=$(IFS=,; echo "${components[*]}")
        fi

        echo "@@@@@@@@ Running admin tests as $USER (for components $components_str) ..."
        echo "-----------------------------------------"
        run_tests "$components_str" "$test_tool_home" "admin" "${verbose_options[@]}" "$@"

        echo "@@@@@@@@ Running tools tests as $test_tool_uid (for components $components_str) ..."
        echo "--------------------------------------------------"
        sudo -i -u "$TEST_TOOL_UID" \
        bash -c \
        "source $test_tool_home/$SOURCE_FILE_NAME && \
        run_tests \"\$@\"" -- "$components_str" "$test_tool_home" "tools" "${verbose_options[@]}" "$@"
    fi

    if is_tool_user "$TEST_TOOL_UID"; then
        echo "Installed toolforge CLIs versions:"
        "${0%/*}"/toolforge_get_versions.sh
        echo -e "\n"

        setup_venv
        setup_toolforge_deploy "$refetch" "$git_branch"

        local components_str="all"
        if [[ ${#components[@]} -gt 0 ]]; then
            for component in "${components[@]}"; do
                local component_dir="${HOME}/toolforge-deploy/components/$component"
                if [[ ! -d "$component_dir" ]]; then
                    echo "The component ${component} doesn't exist. Exiting..."
                    exit 1
                fi
            done
            # create comma separated components string
            components_str=$(IFS=,; echo "${components[*]}")
        fi

        echo "@@@@@@@@ Running tools tests as $test_tool_uid (for components $components_str) ..."
        echo "--------------------------------------------------"
        run_tests "$components_str" "$HOME" "tools" "${verbose_options[@]}" "$@"
    fi
}


# don't run main if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
