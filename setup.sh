#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=./vbox_7.2.6_vm_common.sh
source "${SCRIPT_DIR}/vbox_7.2.6_vm_common.sh"

NAME=${NAME:-debian}
INSTALLER_ISO=${INSTALLER_ISO:-"${SCRIPT_DIR}/images/debian-13-amd64-netinst.iso"}
VDI_IMAGE=${VDI_IMAGE:-"${SCRIPT_DIR}/images/debian-13-nocloud-amd64.vdi"}
DISK_SIZE_MB=${DISK_SIZE_MB:-32768}
VBOX_SOURCE_DIR="${SCRIPT_DIR}/VirtualBox-${VBOX_VERSION}"
VBOX_USER_HOME_DIR=${VBOX_USER_HOME:-"${HOME}/.config/VirtualBox"}
VNC_ENABLED=${VNC_ENABLED:-1}
VNC_ADDRESS=${VNC_ADDRESS:-0.0.0.0}
VNC_PORT=${VNC_PORT:-5910}
VNC_PASSWORD=${VNC_PASSWORD:-}
SERIAL_PORT=${SERIAL_PORT:-5001}
ATTACH_INSTALLER_ISO=1

usage() {
    cat <<EOF
Usage: $(basename "$0") [--no-iso|--noiso]

Options:
  --no-iso, --noiso  Do not attach installer ISO; boot directly from VDI.
  -h, --help         Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-iso|--noiso)
            ATTACH_INSTALLER_ISO=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            vbox_die "Unknown argument: $1"
            ;;
    esac
done

if [[ "$ATTACH_INSTALLER_ISO" == "1" ]]; then
    [[ -f "$INSTALLER_ISO" ]] || vbox_die "Missing installer ISO: ${INSTALLER_ISO}. Run ./download_debian_cloud_vdi.sh first."
fi
[[ "$SERIAL_PORT" =~ ^[0-9]+$ ]] || vbox_die "SERIAL_PORT must be a numeric TCP port."
[[ "$DISK_SIZE_MB" =~ ^[0-9]+$ ]] || vbox_die "DISK_SIZE_MB must be a numeric size in MB."
if [[ "$VNC_ENABLED" == "1" ]]; then
    [[ -n "$VNC_PASSWORD" ]] || vbox_die "Set VNC_PASSWORD when VNC_ENABLED=1."
fi

BIN_DIR=$(vbox_detect_bin_dir "$VBOX_SOURCE_DIR") \
    || vbox_die "Could not find a usable VirtualBox ${VBOX_VERSION} build under ${VBOX_SOURCE_DIR}"

vbox_check_runtime "$BIN_DIR" "$VBOX_USER_HOME_DIR"

if [[ "$VNC_ENABLED" == "1" ]] && ! vbox_manage "$BIN_DIR" list extpacks | awk -F': *' '/^Pack no\./ { if ($2 == "VNC") found=1 } END { exit found ? 0 : 1 }'; then
    vbox_die "VNC_ENABLED=1 but VirtualBox VNC extpack is not installed. Install the VNC extpack from VirtualBox-7.2.6/src/VBox/ExtPacks/VNC."
fi

if vbox_vm_exists "$BIN_DIR" "$NAME"; then
    vbox_die "VM '${NAME}' already exists under ${VBOX_USER_HOME_DIR}. setup.sh is not idempotent; unregister or rename the VM before rerunning it."
fi

vm_created=0
cleanup_partial_vm_on_error() {
    local status=$?
    if [[ $status -ne 0 && $vm_created -eq 1 ]]; then
        if vbox_vm_exists "$BIN_DIR" "$NAME"; then
            vbox_manage "$BIN_DIR" unregistervm "$NAME" >/dev/null 2>&1 || true
        fi
        printf 'Error: setup failed after creating VM "%s"; the partial VM was unregistered. You can rerun setup.sh.\n' "$NAME" >&2
    fi
    return "$status"
}
trap cleanup_partial_vm_on_error ERR

mkdir -p -- "${SCRIPT_DIR}/images"
if [[ ! -f "$VDI_IMAGE" ]]; then
    vbox_manage "$BIN_DIR" createmedium disk --filename "$VDI_IMAGE" --size "$DISK_SIZE_MB" --format VDI
fi

vbox_manage "$BIN_DIR" createvm --name "$NAME" --ostype Debian_64 --register
vm_created=1
vbox_manage "$BIN_DIR" modifyvm "$NAME" \
    --cpus 1 \
    --memory 4096 \
    --vram 128 \
    --graphicscontroller vmsvga \
    --usbohci on \
    --mouse usbtablet \
    --nic1 nat \
    --nictype1 virtio

if ! vbox_manage "$BIN_DIR" storagectl "$NAME" --name "SCSI Controller" --add virtio-scsi --bootable on; then
    vbox_die "Failed to create VirtIO-SCSI controller. This VBoxManage build expects '--add virtio-scsi' for the storage bus."
fi
vbox_manage "$BIN_DIR" storageattach "$NAME" --storagectl "SCSI Controller" --port 0 --device 0 --type hdd --medium "$VDI_IMAGE"
if [[ "$ATTACH_INSTALLER_ISO" == "1" ]]; then
    vbox_manage "$BIN_DIR" storagectl "$NAME" --name "IDE Controller" --add ide
    vbox_manage "$BIN_DIR" storageattach "$NAME" --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "$INSTALLER_ISO"
fi

# Expose guest ttyS0 as a host TCP listener so it can be accessed via telnet.
vbox_manage "$BIN_DIR" modifyvm "$NAME" --uart1 0x3F8 4
vbox_manage "$BIN_DIR" modifyvm "$NAME" --uart-mode1 tcpserver "$SERIAL_PORT"
vbox_manage "$BIN_DIR" modifyvm "$NAME" --uart-type1 16550A

if [[ "$VNC_ENABLED" == "1" ]]; then
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde on
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-extpack VNC
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-address "$VNC_ADDRESS"
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-port "$VNC_PORT"
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde-property "VNCPassword=$VNC_PASSWORD"
else
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --vrde off
fi

vbox_manage "$BIN_DIR" modifyvm "$NAME" --natpf1 "guestssh,tcp,,2223,,22"
if [[ "$ATTACH_INSTALLER_ISO" == "1" ]]; then
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --boot1 dvd --boot2 disk --boot3 none
else
    vbox_manage "$BIN_DIR" modifyvm "$NAME" --boot1 disk --boot2 none --boot3 none
fi

trap - ERR
