#!/bin/bash

set -e

cachedir="$HOME/.cache/bake"
njobs="$(getconf _NPROCESSORS_ONLN)"

packageprefix="$HOME/.local/packages"
envdir="$HOME/.local/environments"

function bake-log {
    echo "$@"
}

function bake-fatal {
    echo "Error: $@"
    exit 1
}

function bake-fetch-source {
    if [[ -z $upstream ]]; then
        echo "Error: 'upstream' variable not defined!"
    fi
    wget -O source.tar.gz "${upstream}"
}

function bake-unpack-source {
    mkdir -p source
    tar xf source.tar.gz -C source --strip-components=1
}

# Function to move cursor and print
function _print_pinned_line {
    # Save cursor position
    tput sc
    # Move to top of screen
    tput cup 0 0
    # Set standout mode
    tput smso
    # Print the pinned line
    echo -n "> $1"
    # Clear to end of line
    tput el
    # Exit standout mode
    tput rmso
    # Restore cursor position
    tput rc
}

function _run_install_step {
    # This should run the command and print a message at the top of the terminal
    # to indicate what's happening.
    # Works okayish, but doesn't look great with fast output and spams the console.
    # Need a more involved approach, something like collecting output in a log file
    # first and printing the tail to the console. Gives control over how many lines
    # are shown.
    $command

    # command=$1
    # message=$2

    # clear
    # echo # Make space for pinned line
    # _print_pinned_line "${message}"
    # $command | while IFS= read -r line; do
    #     echo "$line"
    #     _print_pinned_line "${message}"
    # done
}

function _parse_package_name {
    [[ -z $1 ]] && bake-fatal "No package name provided"

    if [[ "$1" =~ ^[a-zA-Z_]+\/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # User specified package name + custom version
        package=${1%%/*}
        version=${1##*/}
    elif [[ "$1" =~ ^[a-zA-Z_]+$ ]]; then
        # User specified only package name -> use latest version
        package=$1
    else
        bake-fatal "Invalid package name '$1'"
    fi
}

function _prepare_package_cache {
    _parse_package_name $1

    source recipes/${package}

    cachedir="${cachedir}/${package}/${version}"
    sourcedir="${cachedir}/source"
    builddir="${cachedir}/build"
    destdir="${packageprefix}/${package}/${version}"

    export MAKEFLAGS="-sC${builddir} -j${njobs}"

    mkdir -p ${cachedir}
    cd ${cachedir}
}

function _fetch_only {
    _prepare_package_cache $1
    _run_install_step do_fetch "${package}/${version}: Fetching source..."
}

function _unpack_only {
    _prepare_package_cache $1
    _run_install_step do_unpack "${package}/${version}: Unpacking source..."
}

function _config_only {
    _prepare_package_cache $1
    _run_install_step do_config "${package}/${version}: Configuring..."
}

function _build_only {
    _prepare_package_cache $1
    _run_install_step do_build "${package}/${version}: Build..."
}

function _install_only {
    _prepare_package_cache $1
    _run_install_step do_install "${package}/${version}: Install..."
}

function _install {
    _prepare_package_cache $1
    _run_install_step do_fetch "${package}/${version}: Fetching source..."
    _run_install_step do_unpack "${package}/${version}: Unpacking source..."
    _run_install_step do_config "${package}/${version}: Configuring..."
    _run_install_step do_build "${package}/${version}: Build..."
    _run_install_step do_install "${package}/${version}: Install..."
}

function _remove {
    _prepare_package_cache $1
    bake-log "Deleting directory '${destdir}'"
    rm -r "${destdir}"
}

function _list_packages {
    for dir in ${packageprefix}/*/*/
    do
        dir=${dir%*/}                       # remove the trailing "/"
        echo "${dir##${packageprefix}/}"    # print everything after the final "/"
    done
}

function _clear {
    _prepare_package_cache $1
    bake-log "Deleting directory '${cachedir}'"
    rm -r ${cachedir}
}

function _env_subshell_bashrc {
    local envname="$1"
    echo 'if [ -f ~/.bashrc ]; then'
    echo '    source ~/.bashrc'
    echo 'fi'
    echo "BAKE_ENVIRONMENT=${envname}"
    echo "BAKE_ROOT=${envdir}/${envname}"
    echo 'PATH="${BAKE_ROOT}/bin:${PATH}"'
    echo 'PS1="[${BAKE_ENVIRONMENT}] ${PS1}"'
}

function _enter_env {
    [[ -z $1 ]] && bake-fatal "No environment specified."
    local envname="$1"
    bash --rcfile <(_env_subshell_bashrc $envname) -i
}

[[ -z $1 ]] && bake-fatal "No command provided"

case $1 in
    clear )
        shift
        _clear $@
        ;;
    list )
        shift
        _list_packages
        ;;
    install )
        shift
        _install $@
        ;;
    remove )
        shift
        _remove $@
        ;;
    fetch-only )
        shift
        _fetch_only $@
        ;;
    unpack-only )
        shift
        _unpack_only $@
        ;;
    config-only )
        shift
        _config_only $@
        ;;
    build-only )
        shift
        _build_only $@
        ;;
    install-only )
        shift
        _install_only $@
        ;;
    enter )
        shift
        _enter_env $@
        ;;
    * )
        bake-fatal "Unknown command '$1'"
esac
