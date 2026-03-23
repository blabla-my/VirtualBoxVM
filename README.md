# VirtualBoxVM Runbook

This directory contains scripts to build VirtualBox 7.2.6 with clang-based
instrumentation, create a Debian cloud-image VM, and run it headless with VNC.

## What each script does

- `build_vbox_7.2.6_asan.sh`
  - Downloads `VirtualBox-7.2.6.tar.bz2` (if missing).
  - Extracts source (if missing).
  - Applies `vbox_with_clang/VirtualBox-7.2.6-clang.patch` (unless skipped).
  - Runs `vbox_with_clang/build-asan.sh`.
- `build_vbox_7.2.6_coverage.sh`
  - Enters `VirtualBox-7.2.6`, applies patch, runs coverage build helper,
    then reverses patch.
- `download_debian_cloud_vdi.sh`
  - Downloads Debian cloud QCOW2 image + `SHA512SUMS`.
  - Verifies checksum.
  - Converts QCOW2 to VDI under `images/`.
- `setup.sh`
  - Creates and registers VM.
  - Enables VNC via VRDE extpack `VNC`.
  - Generates and attaches cloud-init seed ISO.
  - Uses env `ROOT_PASSWORD` for first-boot root login setup.
  - Configures NAT port forward `host:2223 -> guest:22`.
- `start.sh`
  - Starts VM (default `--type headless`).
- `stop.sh`
  - Powers VM off.

## Prerequisites

Host tools used by these scripts:

- Build flow: `wget`, `tar`, `patch`, `bash`, `readlink`, `sudo`
- Image flow: `qemu-img`, `sha512sum`, and one downloader (`curl` or `wget`)
- Cloud-init seed ISO generation: one of
  `cloud-localds` / `genisoimage` / `mkisofs` / `xorriso`

Runtime assumptions:

- Linux host with required VirtualBox build deps already installed.
- Permission to load VirtualBox kernel modules (`vboxdrv`, `vboxnetflt`,
  `vboxnetadp`) via `sudo`.
- VirtualBox VNC extension pack is installed in the built VirtualBox runtime.

## Quick start

1. Build VirtualBox (ASAN example):

```bash
cd /home/lmy/hypervisors/VirtualBoxVM
./build_vbox_7.2.6_asan.sh
```

2. Download/convert Debian cloud image:

```bash
./download_debian_cloud_vdi.sh
```

3. Create VM and configure credentials via cloud-init:

```bash
VNC_PASSWORD='change_me_vnc' ROOT_PASSWORD='change_me_root' ./setup.sh
```

4. Start VM:

```bash
./start.sh
```

5. Connect:

- VNC: `127.0.0.1:5910` by default (or `${VNC_ADDRESS}:${VNC_PORT}`).
- Guest SSH from host: `ssh -p 2223 root@127.0.0.1` (password is `ROOT_PASSWORD`).

6. Stop VM:

```bash
./stop.sh
```

## Essential behavior and caveats

- `setup.sh` is intentionally not idempotent.
  - It exits if VM `${NAME}` already exists.
  - To re-apply cloud-init/root password changes, recreate VM with a new `NAME`
    or unregister/remove the existing VM first.
- `ROOT_PASSWORD` and `VNC_PASSWORD` are required for `setup.sh`.
- `start.sh` defaults to headless mode unless you pass `--type ...`.
- VNC shows the VM display console (for example `tty1` text login), not serial
  `ttyS0`.

## Environment variables

`setup.sh`:

- `NAME` (default: `debian`)
- `VNC_PASSWORD` (required)
- `ROOT_PASSWORD` (required)
- `VNC_ADDRESS` (default: `0.0.0.0`)
- `VNC_PORT` (default: `5910`)
- `CLOUD_INIT_HOSTNAME` (default: `${NAME}`)
- `VBOX_USER_HOME` (default: `${HOME}/.config/VirtualBox`)

`start.sh`:

- `NAME` (default: `debian`)
- `VBOX_USER_HOME` (default: `${HOME}/.config/VirtualBox`)
- extra args are forwarded to `VBoxManage startvm` (with `--type headless`
  auto-added if absent)

`build_vbox_7.2.6_asan.sh`:

- `JOBS`
- `OUT_BASE_DIR`
- `VBOX_WITH_GCC_SANITIZER_STATIC=1` (optional static sanitizer runtime)

## Useful examples

Reuse an existing tarball/source and skip patch step:

```bash
./build_vbox_7.2.6_asan.sh --skip-download --skip-extract --skip-patch
```

Start VM with explicit GUI type:

```bash
./start.sh --type gui
```
