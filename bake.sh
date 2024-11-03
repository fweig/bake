#!/bin/bash

set -e

cachedir="$HOME/.cache/bake"
njobs="$(getconf _NPROCESSORS_ONLN)"

envdir="$HOME/.local/environments"

function bake-log {
    echo "$@"
}

function bake-fatal {
    echo "Error: $@"
    exit 1
}

# Silent cd when using -
function bake-cd {
    [[ ! -d $1 && $1 != "-" ]] && bake-fatal "No such directory: '$1'"
    cd $1 &>/dev/null
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
    command=$1
    message=$2

    $command

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

function _add_package_to_environment {
    bake-cd ${destdir}
    find . -type d -exec mkdir -p "${BAKE_ROOT}/{}" \;
    find . -type f -exec ln {} "${BAKE_ROOT}/{}" \;
    bake-cd -

    local on_enter_hook=${package}_on_enter
    if [[ $(type -t ${on_enter_hook}) == function ]]; then
        local hookfile=${BAKE_ROOT}/.on_enter/${package}
        cat <(${on_enter_hook}) > $hookfile
        source $hookfile
    fi
}

function _prepare_environment_context {
    [[ -z ${BAKE_ENVIRONMENT} ]] && bake-fatal "Not in an environment. Use 'enter' to enter a environment first."
    [[ -z $BAKE_ROOT ]] && bake-fatal "BAKE_ROOT not defined. Looks like the environment isn't setup properly. Aborting."

    packageprefix=${BAKE_ROOT}/.packages
}

function _prepare_package_cache {

    _prepare_environment_context

    _parse_package_name $1

    source recipes/${package}

    cachedir="${cachedir}/${BAKE_ENVIRONMENT}/${package}/${version}"
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
    _add_package_to_environment
}

function _install {
    _prepare_package_cache $1
    _run_install_step do_fetch "${package}/${version}: Fetching source..."
    _run_install_step do_unpack "${package}/${version}: Unpacking source..."
    _run_install_step do_config "${package}/${version}: Configuring..."
    _run_install_step do_build "${package}/${version}: Build..."
    _run_install_step do_install "${package}/${version}: Install..."
    _add_package_to_environment
}

function _remove {
    _prepare_package_cache $1
    bake-log "Deleting directory '${destdir}'"
    rm -r "${destdir}"
}

function _list_packages {
    _prepare_environment_context
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
    echo "export BAKE_ENVIRONMENT=${envname}"
    echo "export BAKE_ROOT=${envdir}/${envname}"
    echo 'export PATH="${BAKE_ROOT}/bin:${PATH}"'
    echo 'PS1="[${BAKE_ENVIRONMENT}] ${PS1}"'
    echo 'for hook in $(find ${BAKE_ROOT}/.on_enter -type f)'
    echo 'do'
    echo '    source $hook'
    echo 'done'
}

function _enter_env {
    [[ -z $1 ]] && bake-fatal "No environment specified."
    local envname="$1"
    local envroot="${envdir}/${envname}"
    [[ ! -d "${envroot}" ]] && bake-fatal "Couldn't find environment '${envname}'. Use 'create' to make a new environment."
    bash --rcfile <(_env_subshell_bashrc $envname) -i
}

function _bootstrap {
    [[ -z $1 ]] && bake-fatal "No environment specified."
    [[ -z $2 ]] && bake-fatal "No compiler specified."

    env="$1"
    compiler="$2"

    [[ -d $1 ]] && bake-fatal "Environment '${env}' already exists."

    env_root="${envdir}/${env}"
    packageprefix="${env_root}/.packages"
    mkdir -p $packageprefix

    [[ "${compiler}" != "gcc" ]] && bake-fatal "Only 'gcc' is supported as bootstrap compiler at the moment."
}

function _create {
    [[ -z $1 ]] && bake-fatal "No environment specified."
    local envname="$1"
    local envroot="${envdir}/${envname}"

    [[ -d $envroot ]] && bake-fatal "Environment '${envname}' already exists."

    mkdir -p $envroot/.packages
    mkdir -p $envroot/.on_enter
    _enter_env $envname
}

function _entry {
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
        bootstrap )
            shift
            _bootstrap $@
            ;;
        create )
            shift
            _create $@
            ;;
        enter )
            shift
            _enter_env $@
            ;;
        * )
            bake-fatal "Unknown command '$1'"
    esac
}

_entry $@
