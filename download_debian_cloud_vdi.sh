#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_DIR="${SCRIPT_DIR}/images"
SUITE="trixie"
ARCH="amd64"
VARIANT="nocloud"
BASE_URL=""
IMAGE_URL=""
IMAGE_NAME=""
FORCE=0
KEEP_QCOW2=1

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Download a Debian cloud image and convert it to VDI format.

Options:
  --suite <name>         Debian suite used for the default download URL.
                         Default: ${SUITE}
  --arch <name>          Architecture suffix in the image name.
                         Default: ${ARCH}
  --variant <name>       Cloud image variant in the file name.
                         Default: ${VARIANT}
  --base-url <url>       Override the directory that contains the image and SHA512SUMS.
  --url <url>            Full QCOW2 URL. Overrides --suite/--base-url defaults.
  --image-name <name>    Override the QCOW2 file name.
  --output-dir <dir>     Directory for the downloaded QCOW2 and converted VDI.
                         Default: ${OUTPUT_DIR}
  --force                Redownload and reconvert even if files already exist.
  --remove-qcow2         Delete the QCOW2 after conversion.
  --keep-qcow2           Keep the QCOW2 after conversion. Default behavior.
  -h, --help             Show this help text.

Examples:
  $(basename "$0")
  $(basename "$0") --suite trixie --image-name debian-13-nocloud-amd64.qcow2
  $(basename "$0") --url https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
EOF
}

default_image_name() {
  local suite=$1
  local arch=$2
  local variant=$3

  case "$suite" in
    bullseye) printf 'debian-11-%s-%s.qcow2\n' "$variant" "$arch" ;;
    bookworm) printf 'debian-12-%s-%s.qcow2\n' "$variant" "$arch" ;;
    trixie) printf 'debian-13-%s-%s.qcow2\n' "$variant" "$arch" ;;
    *)
      return 1
      ;;
  esac
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  have_command "$1" || die "Missing required command: $1"
}

download_file() {
  local url=$1
  local dest=$2
  local always_download=${3:-0}
  local tmp_path="${dest}.part.$$"

  if [[ -f "$dest" && "$FORCE" -eq 0 && "$always_download" -eq 0 ]]; then
    log "Using existing $(basename "$dest")"
    return 0
  fi

  log "Downloading ${url}"

  if have_command curl; then
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$tmp_path" "$url"
  elif have_command wget; then
    wget -O "$tmp_path" "$url"
  else
    die "Missing required downloader: curl or wget"
  fi

  mv -f -- "$tmp_path" "$dest"
}

verify_checksum() {
  local sums_file=$1
  local image_name=$2
  local expected

  expected=$(awk -v name="$image_name" '
    {
      file = $2
      sub(/^\*/, "", file)
      if (file == name) {
        print $1
        exit
      }
    }
  ' "$sums_file")

  [[ -n "$expected" ]] || die "Could not find checksum for ${image_name} in ${sums_file}"

  log "Verifying SHA512 checksum for ${image_name}"
  printf '%s  %s\n' "$expected" "$image_name" | (
    cd "$OUTPUT_DIR"
    sha512sum -c -
  )
}

convert_to_vdi() {
  local source_path=$1
  local target_path=$2
  local tmp_path="${target_path}.part.$$"

  if [[ -f "$target_path" && "$FORCE" -eq 0 ]]; then
    log "Using existing $(basename "$target_path")"
    return 0
  fi

  log "Converting $(basename "$source_path") to $(basename "$target_path")"
  qemu-img convert -p -f qcow2 -O vdi "$source_path" "$tmp_path"
  mv -f -- "$tmp_path" "$target_path"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      SUITE=$2
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      ARCH=$2
      shift 2
      ;;
    --variant)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      VARIANT=$2
      shift 2
      ;;
    --base-url)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      BASE_URL=$2
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      IMAGE_URL=$2
      shift 2
      ;;
    --image-name)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      IMAGE_NAME=$2
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      OUTPUT_DIR=$2
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --remove-qcow2)
      KEEP_QCOW2=0
      shift
      ;;
    --keep-qcow2)
      KEEP_QCOW2=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_command qemu-img
require_command sha512sum

if [[ -n "$IMAGE_URL" ]]; then
  [[ -n "$BASE_URL" ]] || BASE_URL=${IMAGE_URL%/*}
  [[ -n "$IMAGE_NAME" ]] || IMAGE_NAME=${IMAGE_URL##*/}
else
  [[ -n "$BASE_URL" ]] || BASE_URL="https://cloud.debian.org/images/cloud/${SUITE}/latest"
  if [[ -z "$IMAGE_NAME" ]]; then
    IMAGE_NAME=$(default_image_name "$SUITE" "$ARCH" "$VARIANT") \
      || die "Unknown suite '${SUITE}'. Pass --image-name or --url explicitly."
  fi
  IMAGE_URL="${BASE_URL}/${IMAGE_NAME}"
fi

CHECKSUM_URL="${BASE_URL}/SHA512SUMS"
QCOW_PATH="${OUTPUT_DIR}/${IMAGE_NAME}"
VDI_NAME="${IMAGE_NAME%.qcow2}.vdi"
VDI_PATH="${OUTPUT_DIR}/${VDI_NAME}"
SUMS_PATH="${OUTPUT_DIR}/SHA512SUMS"

mkdir -p -- "$OUTPUT_DIR"

download_file "$CHECKSUM_URL" "$SUMS_PATH" 1
download_file "$IMAGE_URL" "$QCOW_PATH"
verify_checksum "$SUMS_PATH" "$IMAGE_NAME"
convert_to_vdi "$QCOW_PATH" "$VDI_PATH"

if [[ "$KEEP_QCOW2" -eq 0 ]]; then
  log "Removing source QCOW2 image"
  rm -f -- "$QCOW_PATH"
fi

log "Done"
log "QCOW2: ${QCOW_PATH}"
log "VDI:   ${VDI_PATH}"
