#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./vbox_7.2.6_vm_common.sh
source "${SCRIPT_DIR}/vbox_7.2.6_vm_common.sh"

NAME=${NAME:-debian}
VDI_IMAGE="${SCRIPT_DIR}/images/debian-13-nocloud-amd64.vdi"
VBOX_SOURCE_DIR="${SCRIPT_DIR}/VirtualBox-${VBOX_VERSION}"
VBOX_USER_HOME_DIR=${VBOX_USER_HOME:-"${HOME}/.config/VirtualBox"}

[[ -f "$VDI_IMAGE" ]] || vbox_die "Missing disk image: ${VDI_IMAGE}. Run ./download_debian_cloud_vdi.sh first."

BIN_DIR=$(vbox_detect_bin_dir "$VBOX_SOURCE_DIR") \
    || vbox_die "Could not find a usable VirtualBox ${VBOX_VERSION} build under ${VBOX_SOURCE_DIR}"
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
