#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_DIR="${SCRIPT_DIR}/images"
RELEASE_MAJOR="13"
ARCH="amd64"
ISO_FLAVOR="netinst"
BASE_URL=""
ISO_URL=""
ISO_NAME=""
FORCE=0

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

require_command() {
  have_command "$1" || die "Missing required command: $1"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Download Debian installer ISO (default: Debian 13 amd64 netinst) and verify
its SHA256 checksum.

Options:
  --release-major <n>     Debian major release.
                           Default: ${RELEASE_MAJOR}
  --arch <name>           Architecture suffix in the ISO file name.
                           Default: ${ARCH}
  --flavor <name>         Installer flavor in the ISO file name.
                           Default: ${ISO_FLAVOR}
  --base-url <url>        Directory containing ISO + SHA256SUMS.
  --url <url>             Full ISO URL. Overrides --base-url defaults.
  --iso-name <name>       Explicit ISO file name (when --url is not set).
  --output-dir <dir>      Directory to store ISO and checksum file.
                           Default: ${OUTPUT_DIR}
  --force                 Redownload even if local file already exists.
  -h, --help              Show this help text.

Examples:
  $(basename "$0")
  $(basename "$0") --release-major 13 --arch amd64 --flavor netinst
  $(basename "$0") --url https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.1.0-amd64-netinst.iso
EOF
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

resolve_iso_name_from_sums() {
  local sums_file=$1
  local release_major=$2
  local arch=$3
  local flavor=$4

  awk -v release_major="$release_major" -v arch="$arch" -v flavor="$flavor" '
    {
      file = $2
      sub(/^\*/, "", file)
      pattern = "^debian-" release_major "([.][0-9]+)*-" arch "-" flavor "[.]iso$"
      if (file ~ pattern) {
        print file
        exit
      }
    }
  ' "$sums_file"
}

verify_checksum_sha256() {
  local sums_file=$1
  local iso_name=$2
  local expected

  expected=$(awk -v name="$iso_name" '
    {
      file = $2
      sub(/^\*/, "", file)
      if (file == name) {
        print $1
        exit
      }
    }
  ' "$sums_file")

  [[ -n "$expected" ]] || die "Could not find checksum for ${iso_name} in ${sums_file}"

  log "Verifying SHA256 checksum for ${iso_name}"
  printf '%s  %s\n' "$expected" "$iso_name" | (
    cd "$OUTPUT_DIR"
    sha256sum -c -
  )
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-major)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      RELEASE_MAJOR=$2
      shift 2
      ;;
    --arch)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      ARCH=$2
      shift 2
      ;;
    --flavor)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      ISO_FLAVOR=$2
      shift 2
      ;;
    --base-url)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      BASE_URL=$2
      shift 2
      ;;
    --url)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      ISO_URL=$2
      shift 2
      ;;
    --iso-name)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      ISO_NAME=$2
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
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
done

require_command sha256sum

if [[ -n "$ISO_URL" ]]; then
  [[ -n "$BASE_URL" ]] || BASE_URL=${ISO_URL%/*}
  [[ -n "$ISO_NAME" ]] || ISO_NAME=${ISO_URL##*/}
else
  if [[ -z "$BASE_URL" ]]; then
    media_dir="iso-cd"
    if [[ "$ISO_FLAVOR" == DVD-* || "$ISO_FLAVOR" == BD-* ]]; then
      media_dir="iso-dvd"
    fi
    BASE_URL="https://cdimage.debian.org/debian-cd/current/${ARCH}/${media_dir}"
  fi
fi

CHECKSUM_URL="${BASE_URL}/SHA256SUMS"
SUMS_PATH="${OUTPUT_DIR}/SHA256SUMS"
ALIAS_NAME="debian-${RELEASE_MAJOR}-${ARCH}-${ISO_FLAVOR}.iso"
ALIAS_PATH="${OUTPUT_DIR}/${ALIAS_NAME}"

mkdir -p -- "$OUTPUT_DIR"

download_file "$CHECKSUM_URL" "$SUMS_PATH" 1

if [[ -z "$ISO_NAME" ]]; then
  ISO_NAME=$(resolve_iso_name_from_sums "$SUMS_PATH" "$RELEASE_MAJOR" "$ARCH" "$ISO_FLAVOR")
  [[ -n "$ISO_NAME" ]] || die "Could not find matching ISO in SHA256SUMS (release=${RELEASE_MAJOR}, arch=${ARCH}, flavor=${ISO_FLAVOR})."
  ISO_URL="${BASE_URL}/${ISO_NAME}"
elif [[ -z "$ISO_URL" ]]; then
  ISO_URL="${BASE_URL}/${ISO_NAME}"
fi

ISO_PATH="${OUTPUT_DIR}/${ISO_NAME}"

download_file "$ISO_URL" "$ISO_PATH"
verify_checksum_sha256 "$SUMS_PATH" "$ISO_NAME"

if [[ "$ISO_NAME" != "$ALIAS_NAME" ]]; then
  ln -sfn "$ISO_NAME" "$ALIAS_PATH"
  log "Alias: ${ALIAS_PATH} -> ${ISO_NAME}"
else
  log "Alias: ${ALIAS_PATH}"
fi

log "Done"
log "ISO:   ${ISO_PATH}"
