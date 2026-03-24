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

vbox_ensure_kernel_modules_loaded() {
    local -a required_modules=(vboxdrv vboxnetflt vboxnetadp)
    local -a missing_modules=()
    local -a modprobe_cmd=(modprobe)
    local module

    [[ "$(uname -s)" == "Linux" ]] || return 0

    for module in "${required_modules[@]}"; do
        if ! vbox_module_loaded "$module"; then
            missing_modules+=("$module")
        fi
    done

    [[ ${#missing_modules[@]} -eq 0 ]] && return 0

    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 \
            || vbox_die "VirtualBox kernel modules are not loaded (${missing_modules[*]}) and sudo is not available to load them."
        modprobe_cmd=(sudo modprobe)
    fi

    vbox_log "Loading missing VirtualBox kernel modules: ${missing_modules[*]}"
    for module in "${missing_modules[@]}"; do
        "${modprobe_cmd[@]}" "$module" \
            || vbox_die "Failed to load kernel module '${module}' using modprobe (no rebuild attempted)."
    done
}

[[ -f "$VDI_IMAGE" ]] || vbox_die "Missing disk image: ${VDI_IMAGE}. Run ./download_debian_cloud_vdi.sh first."

BIN_DIR=$(vbox_detect_bin_dir "$VBOX_SOURCE_DIR") \
    || vbox_die "Could not find a usable VirtualBox ${VBOX_VERSION} build under ${VBOX_SOURCE_DIR}"
vbox_ensure_kernel_modules_loaded
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
