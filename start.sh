#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./vbox_7.2.6_vm_common.sh
source "${SCRIPT_DIR}/vbox_7.2.6_vm_common.sh"

NAME=${NAME:-debian}
VDI_IMAGE="${SCRIPT_DIR}/images/debian-13-nocloud-amd64.vdi"
VBOX_SOURCE_DIR="${SCRIPT_DIR}/VirtualBox-${VBOX_VERSION}"
VBOX_USER_HOME_DIR=${VBOX_USER_HOME:-"${HOME}/.config/VirtualBox"}

vbox_module_loaded() {
    local module=$1
    [[ -d "/sys/module/${module}" ]]
}

vbox_find_built_module() {
    local bin_dir=$1
    local module=$2
    local -a candidates=(
        "${bin_dir}/src/${module}.ko"
        "${bin_dir}/src/${module}/${module}.ko"
    )
    local candidate

    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

vbox_insert_built_module() {
    local bin_dir=$1
    local module=$2
    local module_path
    local insmod_bin
    local -a insmod_cmd

    module_path=$(vbox_find_built_module "$bin_dir" "$module") || vbox_die \
        "Kernel module '${module}' is not present under ${bin_dir}/src (expected build output). Refusing to rebuild in start.sh."

    insmod_bin=$(command -v insmod 2>/dev/null || true)
    if [[ -z "$insmod_bin" && -x /sbin/insmod ]]; then
        insmod_bin=/sbin/insmod
    fi
    [[ -n "$insmod_bin" ]] || vbox_die "Could not find 'insmod' to load ${module_path}."

    insmod_cmd=("$insmod_bin")
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 \
            || vbox_die "Need root privileges to load '${module}' from ${module_path}, but sudo is not available."
        insmod_cmd=(sudo "$insmod_bin")
    fi

    "${insmod_cmd[@]}" "$module_path" \
        || vbox_die "Failed to load built module '${module}' from ${module_path}."
}

vbox_ensure_kernel_modules_loaded() {
    local bin_dir=$1
    local -a required_modules=(vboxdrv vboxnetflt vboxnetadp)
    local -a missing_modules=()
    local module

    [[ "$(uname -s)" == "Linux" ]] || return 0

    for module in "${required_modules[@]}"; do
        if ! vbox_module_loaded "$module"; then
            missing_modules+=("$module")
        fi
    done

    [[ ${#missing_modules[@]} -eq 0 ]] && return 0

    vbox_log "Loading missing VirtualBox kernel modules from build output: ${missing_modules[*]}"
    for module in "${missing_modules[@]}"; do
        vbox_insert_built_module "$bin_dir" "$module"
    done
}

[[ -f "$VDI_IMAGE" ]] || vbox_die "Missing disk image: ${VDI_IMAGE}. Run ./download_debian_cloud_vdi.sh first."

BIN_DIR=$(vbox_detect_bin_dir "$VBOX_SOURCE_DIR") \
    || vbox_die "Could not find a usable VirtualBox ${VBOX_VERSION} build under ${VBOX_SOURCE_DIR}"
vbox_ensure_kernel_modules_loaded "$BIN_DIR"
vbox_check_runtime "$BIN_DIR" "$VBOX_USER_HOME_DIR"
vbox_vm_exists "$BIN_DIR" "$NAME" \
    || vbox_die "VM '${NAME}' is not registered in ${VBOX_USER_HOME_DIR}. Run ./setup.sh first or set NAME=<vm>."

start_args=("$@")
if [[ ${#start_args[@]} -eq 0 ]]; then
    start_args=(--type headless)
else
    has_type=0
    for arg in "${start_args[@]}"; do
        if [[ "$arg" == "--type" || "$arg" == --type=* ]]; then
            has_type=1
            break
        fi
    done

    if [[ $has_type -eq 0 ]]; then
        start_args=(--type headless "${start_args[@]}")
    fi
fi

vbox_manage "$BIN_DIR" startvm "$NAME" "${start_args[@]}"
