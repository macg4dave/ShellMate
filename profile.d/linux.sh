#------------------------------------------------------------------------------
# Linux helpers (plugin-friendly entry point)
#------------------------------------------------------------------------------

# shellcheck shell=bash

[[ "${IS_LINUX:-false}" == "true" ]] || return 0

# Keep this file safe to source on any host and avoid hard dependencies.

#------------------------------------------------------------------------------
## WSL: readable ls colours on Windows drives
# Windows drives (/mnt/c, ...) are mounted with every file 0777 by default, so
# GNU ls paints every directory as "other-writable" (blue on green). Show those
# directories like normal ones instead. Only applies on WSL, and only when the
# user hasn't already chosen their own ow=/tw= colours.
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
## WSL: don't show every file on a Windows drive as a program
# Without the drvfs "metadata" mount option every file there is executable, so
# `ls` would paint them all bold green and add a `*`. On those mounts list them
# with no "executable" colour and only / @ | = markers. Mounts are read lazily,
# on the first `ls`, never at source time.
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
    local a plain=0 has_path=0
    for a in "$@"; do
        case "$a" in -*) continue ;; esac
        has_path=1
        _linux_wsl_on_plain_mount "$a" && plain=1
    done
    if [[ "$has_path" -eq 0 ]] && _linux_wsl_on_plain_mount "$PWD"; then
        plain=1
    fi
    if [[ "$plain" -eq 1 ]]; then
        LS_COLORS="${LS_COLORS:+${LS_COLORS%:}:}ex=00" command ls --color=auto --file-type -hla "$@"
    else
        command ls --color=auto -Fhla "$@"
    fi
}

if _linux_is_wsl; then
    case ":${LS_COLORS:-}:" in
        *:ow=*|*:tw=*) ;;
        *) export LS_COLORS="${LS_COLORS:+${LS_COLORS%:}:}ow=01;34:tw=01;34" ;;
    esac
    alias ls='_linux_wsl_ls'
    __BP_LS_FUNC="_linux_wsl_ls"   # the cd hook in 10-common.sh lists with this
fi
