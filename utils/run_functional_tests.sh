#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

TOOLFORGE_DEPLOY_URL="https://gitlab.wikimedia.org/repos/cloud/toolforge/toolforge-deploy"
declare -A DEFAULT_TEST_TOOLS_PER_ENV
DEFAULT_TEST_TOOLS_PER_ENV["local"]="tf-test"
DEFAULT_TEST_TOOLS_PER_ENV["toolsbeta"]="test"
DEFAULT_TEST_TOOLS_PER_ENV["tools"]="automated-toolforge-tests"


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

            -t|--test-tool
                Name of the tool to use for the testing without prefix (ex. tf-test or wm-lol)

            -v|--verbose
                If passed, it will use extra verbose options to show extra logs.

        Arguments:
            extra-args
                If passed, it will be passed as-is to bats as extra arguments.
                Usefule for example to filter tests to run, for example:
                    To filter by test name:
                    * --filter '.*continuous-job.*'

                    To filter by tag (toloforge component):
                    * --filter-tags jobs-api

                Note the -- separating this from the options.


        Example:
            To run in toolforge deployment using the wm-lol tool as test tool and fetching the latest test:

            toolforge> $0 --refetch-tests --test-tool wm-lol

EOH
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


setup_venv() {
    if ! [[ -e "$HOME/venv/bin/activate" ]]; then
        if inside_toolforge_deployment; then
            # shellcheck disable=SC2016
            webservice python3.11 shell -- bash -c 'python3 -m venv "$TOOL_DATA_DIR/venv"'
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
    if ! [[ -e "$HOME"/toolforge-deploy ]]; then
        git clone "$TOOLFORGE_DEPLOY_URL" "$HOME"/toolforge-deploy
    fi

    if [[ "$refetch" == "yes" ]]; then
        cd "$HOME"/toolforge-deploy
        git fetch --all 2>/dev/null
        git reset --hard FETCH_HEAD
        cd -
    fi
}

setup_environment() {
    local refetch="${1?}"
    setup_venv
    setup_toolforge_deploy "$refetch"
}


main() {
    local refetch="no"
    local verbose="no"
    local opts \
        current_project \
        passed_args \
        test_tool_name="" \
        test_tool_uid


    passed_args=("$@")
    opts=$(getopt -o 'hrvt:' --long 'help,verbose,refetch-tests,test-tool' -n "$0" -- "$@")
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
    fi

    if ! id -u "$test_tool_uid" &>/dev/null; then
        echo "Unable to find user for tool $test_tool_name (uid:$test_tool_uid). If running in tools/toolsbeta, you should specify one with -t"
        exit 1
    fi

    if [[ "$USER" != "$test_tool_uid" ]]; then
        sudo -i -u "$test_tool_uid" "$(realpath "$0")" "${passed_args[@]}"
        exit $?
    fi

    setup_environment "$refetch"

    local verbose_options=(
        "--print-output-on-failure"
    )
    if [[ "$verbose" == "yes" ]]; then
        verbose_options=(
            "--show-output-of-passing-tests"
            "--trace"
        )
    fi

    # we need to be in the home of the tool, where the jobs will create the logs
    cd ~
    bats_core_pkg \
        --verbose-run \
        --pretty \
        --timing \
        --recursive \
        --setup-suite-file "$HOME"/toolforge-deploy/functional-tests/setup_suite.bash \
        "${verbose_options[@]}" \
        "$@" \
        "$HOME"/toolforge-deploy/functional-tests
}


main "$@"
