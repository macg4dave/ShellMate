#------------------------------------------------------------------------------
# Linux helpers (plugin-friendly entry point)
#------------------------------------------------------------------------------

# shellcheck shell=bash

[[ "${IS_LINUX:-false}" == "true" ]] || return 0

# Keep this file safe to source on any host and avoid hard dependencies.

#------------------------------------------------------------------------------
## WSL detection
#------------------------------------------------------------------------------

_linux_is_wsl() {
    local rel=""
    [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
    [[ -r /proc/sys/kernel/osrelease ]] || return 1
    IFS= read -r rel < /proc/sys/kernel/osrelease 2>/dev/null || true
    case "$rel" in
        *[Mm]icrosoft*) return 0 ;;
    esac
    return 1
}

#------------------------------------------------------------------------------
## WSL: readable `ls` on Windows drives
# Without the drvfs "metadata" mount option every file and folder on a Windows
# drive (/mnt/c, ...) is 0777, so `ls` would paint every file bold green with a
# `*` (executable) and every folder blue on green (other-writable). On those
# mounts, list files plainly and folders in their own colour:
#   BASH_PROFILE_WSL_DIR_COLOR   SGR code for folders (default 01;33;40, bright
#                                yellow on black; e.g. 01;34 for normal blue)
# The colours are added last, so they win over LS_COLORS from dircolors in
# ~/.bashrc. Mounts are read lazily, on the first `ls`, never at source time.
#------------------------------------------------------------------------------

_linux_wsl_mounts_file="/proc/mounts"
_linux_wsl_plain_mounts=""
_linux_wsl_mounts_read=0

# Collect drvfs mount points that don't have Linux permissions.
_linux_wsl_read_mounts() {
    local mnt type opts rest
    _linux_wsl_mounts_read=1
    _linux_wsl_plain_mounts=""
    [[ -r "$_linux_wsl_mounts_file" ]] || return 0
    while IFS=$' \t' read -r _ mnt type opts rest; do
        case "$type" in
            drvfs) ;;
            9p) case "$opts" in *aname=drvfs*) ;; *) continue ;; esac ;;
            *) continue ;;
        esac
        case "$opts" in *metadata*) continue ;; esac
        _linux_wsl_plain_mounts="${_linux_wsl_plain_mounts}${mnt}"$'\n'
    done < "$_linux_wsl_mounts_file"
}

# Usage: _linux_wsl_on_plain_mount <path>   (relative paths are from $PWD)
_linux_wsl_on_plain_mount() {
    local p="$1" m IFS=$'\n'
    [[ "$p" == /* ]] || p="$PWD/$p"
    [[ "$_linux_wsl_mounts_read" -eq 1 ]] || _linux_wsl_read_mounts
    for m in $_linux_wsl_plain_mounts; do
        [[ "$m" == "/" ]] && return 0
        case "$p/" in "$m"/*) return 0 ;; esac
    done
    return 1
}

# Same listing as the `ls` alias, minus the "everything is a program" look on
# Windows drives. Decides from the paths given, or from $PWD when there are none.
_linux_wsl_ls() {
    local a plain=0 has_path=0 dir_color="${BASH_PROFILE_WSL_DIR_COLOR:-01;33;40}"
    case "$dir_color" in
        ""|*[!0-9\;]*) dir_color="01;33;40" ;;
    esac
    for a in "$@"; do
        case "$a" in -*) continue ;; esac
        has_path=1
        _linux_wsl_on_plain_mount "$a" && plain=1
    done
    if [[ "$has_path" -eq 0 ]] && _linux_wsl_on_plain_mount "$PWD"; then
        plain=1
    fi
    if [[ "$plain" -eq 1 ]]; then
        LS_COLORS="${LS_COLORS:+${LS_COLORS%:}:}ex=00:di=$dir_color:ow=$dir_color:tw=$dir_color" \
            command ls --color=auto --file-type -hla "$@"
    else
        command ls --color=auto -Fhla "$@"
    fi
}

if _linux_is_wsl; then
    alias ls='_linux_wsl_ls'
    __BP_LS_FUNC="_linux_wsl_ls"   # the cd hook in 10-common.sh lists with this
fi
