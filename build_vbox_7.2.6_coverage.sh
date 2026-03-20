#!/usr/bin/env bash
set -euo pipefail

VERSION="7.2.6"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR="$SCRIPT_DIR"
HELPER_DIR="$SCRIPT_DIR/vbox_with_clang"
TARBALL_URL="https://download.virtualbox.org/virtualbox/${VERSION}/VirtualBox-${VERSION}.tar.bz2"
TARBALL_PATH="$WORK_DIR/VirtualBox-${VERSION}.tar.bz2"
SOURCE_DIR="$WORK_DIR/VirtualBox-${VERSION}"
PATCH_PATH="$HELPER_DIR/VirtualBox-${VERSION}-clang.patch"
SKIP_DOWNLOAD=0
SKIP_EXTRACT=0
SKIP_PATCH=0

log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [-- <kmk targets or args...>]

Download VirtualBox ${VERSION}, apply the local clang patch, and build the
coverage-instrumented userspace targets via vbox_with_clang/build-coverage.sh.

Options:
  --work-dir <dir>      Directory that will hold the tarball and source tree.
                        Default: ${WORK_DIR}
  --tarball <path>      Tarball path.
                        Default: ${TARBALL_PATH}
  --source-dir <dir>    Source tree path.
                        Default: ${SOURCE_DIR}
  --skip-download       Reuse the existing tarball and do not run wget.
  --skip-extract        Reuse the existing extracted source tree.
  --skip-patch          Skip applying the clang patch.
  -h, --help            Show this help text.

Environment:
  JOBS=<n>              Passed through to vbox_with_clang/build-coverage.sh.
  OUT_BASE_DIR=<dir>    Override the coverage build output directory.
  PROFILE_DIR=<dir>     Override the LLVM raw profile directory.

Examples:
  $(basename "$0")
  JOBS=32 $(basename "$0")
  OUT_BASE_DIR=/tmp/vbox-cov $(basename "$0")
  OUT_BASE_DIR=/tmp/vbox-cov $(basename "$0") -- VBoxHeadless VBoxManage VBoxSVC \
    VBoxCAPI VBoxXPCOMIPCC VBoxSVCM VBoxC
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

download_tarball() {
    if [[ "$SKIP_DOWNLOAD" -eq 1 ]]; then
        [[ -f "$TARBALL_PATH" ]] || die "--skip-download was set but ${TARBALL_PATH} does not exist"
        log "Skipping download"
        return 0
    fi

    if [[ -f "$TARBALL_PATH" ]]; then
        log "Using existing tarball ${TARBALL_PATH}"
        return 0
    fi

    mkdir -p -- "$(dirname -- "$TARBALL_PATH")"
    log "Downloading ${TARBALL_URL}"
    wget -O "$TARBALL_PATH" "$TARBALL_URL"
}

extract_source() {
    local extract_parent
    local extracted_default_dir

    if [[ "$SKIP_EXTRACT" -eq 1 ]]; then
        [[ -d "$SOURCE_DIR" ]] || die "--skip-extract was set but ${SOURCE_DIR} does not exist"
        log "Skipping extraction"
        return 0
    fi

    if [[ -d "$SOURCE_DIR" ]]; then
        log "Using existing source tree ${SOURCE_DIR}"
        return 0
    fi

    extract_parent=$(dirname -- "$SOURCE_DIR")
    extracted_default_dir="${extract_parent}/VirtualBox-${VERSION}"
    mkdir -p -- "$extract_parent"
    log "Extracting ${TARBALL_PATH}"
    tar -C "$extract_parent" -xf "$TARBALL_PATH"

    if [[ "$SOURCE_DIR" != "$extracted_default_dir" ]]; then
        [[ -d "$extracted_default_dir" ]] || die "Expected extracted tree ${extracted_default_dir}"
        [[ ! -e "$SOURCE_DIR" ]] || die "Refusing to overwrite existing ${SOURCE_DIR}"
        mv -- "$extracted_default_dir" "$SOURCE_DIR"
    fi

    [[ -d "$SOURCE_DIR" ]] || die "Expected source tree ${SOURCE_DIR} after extraction"
}

apply_patch_if_needed() {
    if [[ "$SKIP_PATCH" -eq 1 ]]; then
        log "Skipping patch application"
        return 0
    fi

    if patch -d "$SOURCE_DIR" -p1 --dry-run < "$PATCH_PATH" >/dev/null 2>&1; then
        log "Applying ${PATCH_PATH}"
        patch -d "$SOURCE_DIR" -p1 < "$PATCH_PATH"
        return 0
    fi

    if patch -d "$SOURCE_DIR" -R -p1 --dry-run < "$PATCH_PATH" >/dev/null 2>&1; then
        log "Patch already applied"
        return 0
    fi

    die "Could not apply ${PATCH_PATH}; the source tree may already be modified"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            WORK_DIR=$2
            TARBALL_PATH="$WORK_DIR/VirtualBox-${VERSION}.tar.bz2"
            SOURCE_DIR="$WORK_DIR/VirtualBox-${VERSION}"
            shift 2
            ;;
        --tarball)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            TARBALL_PATH=$2
            shift 2
            ;;
        --source-dir)
            [[ $# -ge 2 ]] || die "Missing value for $1"
            SOURCE_DIR=$2
            shift 2
            ;;
        --skip-download)
            SKIP_DOWNLOAD=1
            shift
            ;;
        --skip-extract)
            SKIP_EXTRACT=1
            shift
            ;;
        --skip-patch)
            SKIP_PATCH=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

have_explicit_target=0
for arg in "$@"; do
    case "$arg" in
        -*|*=*)
            ;;
        *)
            have_explicit_target=1
            ;;
    esac
done

if [[ $# -eq 0 || "$have_explicit_target" -eq 0 ]]; then
    set -- "$@" \
        VBoxHeadless \
        VBoxManage \
        VBoxSVC \
        VBoxCAPI \
        VBoxXPCOMIPCC \
        VBoxSVCM \
        VBoxC
fi

require_command wget
require_command tar
require_command patch
require_command bash
require_command readlink

HELPER_DIR=$(readlink -f -- "$HELPER_DIR")
TARBALL_PATH=$(readlink -m -- "$TARBALL_PATH")
SOURCE_DIR=$(readlink -m -- "$SOURCE_DIR")
PATCH_PATH=$(readlink -f -- "$PATCH_PATH")

[[ -d "$HELPER_DIR" ]] || die "Missing helper directory: ${HELPER_DIR}"
[[ -f "$HELPER_DIR/build-coverage.sh" ]] || die "Missing helper script: ${HELPER_DIR}/build-coverage.sh"
[[ -f "$PATCH_PATH" ]] || die "Missing patch: ${PATCH_PATH}"

download_tarball
extract_source
apply_patch_if_needed

log "Starting coverage build in ${SOURCE_DIR}"
bash "$HELPER_DIR/build-coverage.sh" "$SOURCE_DIR" "$@"
