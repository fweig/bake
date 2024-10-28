#!/bin/bash

set -e

cachedir="$HOME/.cache/bake"
njobs="$(getconf _NPROCESSORS_ONLN)"

packageprefix="$HOME/.local/packages"
envdir="$HOME/.local/environments"

function bake-log {
    echo "$@"
}

function bake-unpack-source {
    mkdir -p source
    tar xf ${1} -C source --strip-components=1
}

# Function to move cursor and print
function _print_pinned_line {
    # Save cursor position
    echo -en "\033[s"
    # Move to top of screen
    echo -en "\033[0;0H"
    # Print the pinned line
    echo -en ">>> $1"
    # Clear to end of line
    echo -en "\033[K"
    # Restore cursor position
    echo -en "\033[u"
}

function _run_install_step {
    command=$1
    message=$2

    clear
    _print_pinned_line "${message}"
    $command | while IFS= read -r line; do
        echo "$line"
        _print_pinned_line "${message}"
    done
}

function _parse_package_name {
    if [[ -z $1 ]]; then
        echo "No package name provided"
        exit 1
    fi
    package=${1%%/*}
    version=${1##*/}
    cachedir="${cachedir}/${package}/${version}"
}

function _prepare_package_cache {
    _parse_package_name $1

    source recipes/${package}

    mkdir -p ${cachedir}
    cd ${cachedir}

    sourcedir="${cachedir}/source"
    builddir="${cachedir}/build"
    destdir="${packageprefix}/${package}/${version}"

    export MAKEFLAGS="-sC${builddir} -j${njobs}"
}

function _fetch_only {
    _prepare_package_cache $1
    do_fetch
}

function _unpack_only {
    _prepare_package_cache $1
    do_unpack
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
    _parse_package_name $1
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
    if [[ -z $1 ]]; then
        echo "Error: No environment specified"
        exit 1
    fi
    local envname="$1"
    bash --rcfile <(_env_subshell_bashrc $envname) -i
}

if [[ -z $1 ]]; then
    echo "Error: No command provided"
    exit 1
fi

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
        echo "Unknow command '${1}'"
        exit 1
esac
