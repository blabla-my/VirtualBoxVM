#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./vbox_7.2.6_vm_common.sh
source "${SCRIPT_DIR}/vbox_7.2.6_vm_common.sh"

NAME=${NAME:-debian}
VDI_IMAGE="${SCRIPT_DIR}/images/debian-13-nocloud-amd64.vdi"
VBOX_SOURCE_DIR="${SCRIPT_DIR}/VirtualBox-${VBOX_VERSION}"
VBOX_USER_HOME_DIR=${VBOX_USER_HOME:-"${HOME}/.config/VirtualBox"}
VNC_ADDRESS=${VNC_ADDRESS:-0.0.0.0}
VNC_PORT=${VNC_PORT:-5910}
VNC_PASSWORD=${VNC_PASSWORD:-}

[[ -f "$VDI_IMAGE" ]] || vbox_die "Missing disk image: ${VDI_IMAGE}. Run ./download_debian_cloud_vdi.sh first."
[[ -n "$VNC_PASSWORD" ]] || vbox_die "Set VNC_PASSWORD before running setup.sh. The VirtualBox VNC backend requires a clear-text password."

BIN_DIR=$(vbox_detect_bin_dir "$VBOX_SOURCE_DIR") \
    || vbox_die "Could not find a usable VirtualBox ${VBOX_VERSION} build under ${VBOX_SOURCE_DIR}"

vbox_check_runtime "$BIN_DIR" "$VBOX_USER_HOME_DIR"

if ! vbox_manage "$BIN_DIR" list extpacks | awk -F': *' '/^Pack no\./ { if ($2 == "VNC") found=1 } END { exit found ? 0 : 1 }'; then
    vbox_die "VirtualBox VNC extpack is not installed. Install the VNC extpack from VirtualBox-7.2.6/src/VBox/ExtPacks/VNC before using setup.sh."
fi

if vbox_vm_exists "$BIN_DIR" "$NAME"; then
    vbox_die "VM '${NAME}' already exists under ${VBOX_USER_HOME_DIR}. setup.sh is not idempotent; unregister or rename the VM before rerunning it."
fi

vbox_manage "$BIN_DIR" createvm --name "$NAME" --ostype Debian_64 --register
vbox_manage "$BIN_DIR" modifyvm "$NAME" \
    --cpus 4 \
    --memory 1024 \
    --vram 128 \
    --graphicscontroller vmsvga \
    --usbohci on \
    --mouse usbtablet \
    --nic1 nat

vbox_manage "$BIN_DIR" storagectl "$NAME" --name "SATA Controller" --add sata --bootable on
vbox_manage "$BIN_DIR" storageattach "$NAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$VDI_IMAGE"
vbox_manage "$BIN_DIR" storagectl "$NAME" --name "IDE Controller" --add ide

# Enable VNC access via the VirtualBox VNC VRDE extension pack.
vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde on
vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-extpack VNC
vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-address "$VNC_ADDRESS"
vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-port "$VNC_PORT"
vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-property "VNCPassword=$VNC_PASSWORD"

vbox_manage "$BIN_DIR" modifyvm "$NAME" --natpf1 "guestssh,tcp,,2223,,22"
vbox_manage "$BIN_DIR" modifyvm "$NAME" --boot1 disk --boot2 dvd --boot3 none
