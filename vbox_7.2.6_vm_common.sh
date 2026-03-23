#!/usr/bin/env bash
# shellcheck shell=bash

VBOX_VERSION="7.2.6"

vbox_log() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

vbox_die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

vbox_require_command() {
    command -v "$1" >/dev/null 2>&1 || vbox_die "Missing required command: $1"
}

vbox_append_path() {
    local dir=$1

    case ":${PATH:-}:" in
        *":${dir}:"*)
            ;;
        *)
            if [[ -n "${PATH:-}" ]]; then
                PATH="${PATH}:${dir}"
            else
                PATH="${dir}"
            fi
            ;;
    esac

    export PATH
}

vbox_validate_bin_dir() {
    local bin_dir=$1

    [[ -d "$bin_dir" ]] || return 1
    [[ -x "$bin_dir/VBoxManage" ]] || return 1
    [[ -x "$bin_dir/VBoxHeadless" ]] || return 1
    [[ -x "$bin_dir/VBoxSVC" ]] || return 1
    [[ -f "$bin_dir/VBoxXPCOM.so" ]] || return 1
    [[ -f "$bin_dir/VBoxXPCOMIPCD.so" ]] || return 1
    [[ -f "$bin_dir/VBoxXPCOMC.so" ]] || return 1
    [[ -f "$bin_dir/components/VirtualBox_XPCOM.xpt" ]] || return 1
    [[ -f "$bin_dir/components/VBoxXPCOMIPCC.so" ]] || return 1
    [[ -f "$bin_dir/components/VBoxSVCM.so" ]] || return 1
    [[ -f "$bin_dir/components/VBoxC.so" ]] || return 1
}

vbox_find_bin_dir_in_tree() {
    local search_root=$1
    local bin_path
    local bin_dir

    [[ -d "$search_root" ]] || return 1

    while IFS= read -r -d '' bin_path; do
        bin_dir=$(dirname -- "$bin_path")
        if vbox_validate_bin_dir "$bin_dir"; then
            printf '%s\n' "$bin_dir"
            return 0
        fi
    done < <(find "$search_root" -type f -path '*/bin/VBoxManage' -print0 2>/dev/null | sort -z)

    return 1
}

vbox_detect_bin_dir() {
    local source_dir=$1
    local bin_dir

    if bin_dir=$(vbox_find_bin_dir_in_tree "$source_dir/out-clang-coverage"); then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    if bin_dir=$(vbox_find_bin_dir_in_tree "$source_dir"); then
        printf '%s\n' "$bin_dir"
        return 0
    fi

    return 1
}

vbox_prepare_runtime_env() {
    local bin_dir=$1
    local vbox_user_home=$2

    mkdir -p -- "$vbox_user_home"
    vbox_append_path "$bin_dir"
    export VBOX_USER_HOME="$vbox_user_home"
}

vbox_manage() {
    local bin_dir=$1
    shift

    "$bin_dir/VBoxManage" "$@"
}

vbox_runtime_permission_hint() {
    local hints=()

    if [[ -e /dev/vboxdrv && ! ( -r /dev/vboxdrv && -w /dev/vboxdrv ) ]]; then
        hints+=("/dev/vboxdrv")
    fi

    if [[ -e /dev/vboxdrvu && ! ( -r /dev/vboxdrvu && -w /dev/vboxdrvu ) ]]; then
        hints+=("/dev/vboxdrvu")
    fi

    if [[ ${#hints[@]} -gt 0 ]]; then
        printf ' Current user cannot access %s; rerun the build helper or fix the device-node permissions.' "${hints[*]}"
    fi
}

vbox_check_runtime() {
    local bin_dir=$1
    local vbox_user_home=$2
    local output
    local permission_hint=""

    vbox_prepare_runtime_env "$bin_dir" "$vbox_user_home"
    permission_hint=$(vbox_runtime_permission_hint)

    if ! output=$(vbox_manage "$bin_dir" list systemproperties 2>&1); then
        printf '%s\n' "$output" >&2
        vbox_die "Detected build at ${bin_dir}, but VBoxManage could not initialize VirtualBox.${permission_hint} Check ${vbox_user_home}/VBoxSVC.log for host/runtime details."
    fi
}

vbox_vm_exists() {
    local bin_dir=$1
    local vm_name=$2

    vbox_manage "$bin_dir" showvminfo "$vm_name" >/dev/null 2>&1
}

vbox_medium_usage() {
    local bin_dir=$1
    local medium_path=$2
    local info

    if ! info=$(vbox_manage "$bin_dir" showmediuminfo disk "$medium_path" 2>/dev/null); then
        return 1
    fi

    awk -F':[[:space:]]*' '/^In use by VMs:/ {print $2; exit}' <<<"$info"
}
