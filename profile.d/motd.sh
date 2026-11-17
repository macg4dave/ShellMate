#------------------------------------------------------------------------------
# motd: message of the day for interactive shells
#
# - First BASH_PROFILE_MOTD_TIMES (default 3) interactive shells: a short
#   ShellMate welcome with basic usage, then it stops by itself.
# - Your own message (motd --edit) is shown at every interactive shell instead.
# - motd --off / --on turns the automatic message off / back on.
#
# Safe to source: does nothing unless the shell is interactive; prints to
# stderr only; starts no processes once the welcome has run its course; the
# only write is a tiny counter under ${XDG_STATE_HOME:-~/.local/state}.
#------------------------------------------------------------------------------

# shellcheck shell=bash

# Keep these two paths in sync with _motd_autoshow (which inlines them).
_motd_config_file() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/my-mac-bash-profile/motd"
}

_motd_state_dir() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/my-mac-bash-profile"
}

_motd_times() {
    local times="${BASH_PROFILE_MOTD_TIMES:-3}"
    [[ "$times" =~ ^[0-9]+$ ]] || times=3
    printf '%s\n' "$times"
}

# Print a text file using builtins only (never executes its contents).
_motd_print_file() {
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        printf '%s\n' "$line"
    done < "$1"
}

_motd_welcome() {
    # Usage: _motd_welcome [shown_count]
    local shown="${1:-}" times
    times="$(_motd_times)"
    cat <<'EOF'
Welcome to ShellMate - handy helpers for your shell:

  sysinfo        system overview (CPU, RAM, disk, uptime)
  netinfo        network summary (IPs, gateway, VPN)
  extract FILE   unpack almost any archive
  pathinfo       check PATH for duplicates / missing dirs
  flushdns       flush the DNS cache
  jd URL         download a file (wget, resumable)

  Add --help to any of them for details.

EOF
    if [[ -n "$shown" ]]; then
        printf 'This message shows %s of %s times. Change it:\n' "$shown" "$times"
    else
        printf 'Change this message:\n'
    fi
    cat <<'EOF'
  motd --edit    write your own message (shown at every login)
  motd --off     stop showing a message at login
  motd --help    all options
EOF
}

_motd_usage() {
    cat <<'USAGE'
Usage: motd [--help] [--edit] [--off] [--on]

Show the message of the day. With no options, print it now.

Options:
  -h, --help   Show this help and exit.
  --edit       Edit your own message in $VISUAL / $EDITOR (shown at every login).
               Delete the file to go back to the ShellMate welcome.
  --off        Don't show a message when a shell starts.
  --on         Show it again (also restarts the welcome count).

Files:
  ~/.config/my-mac-bash-profile/motd        your message (plain text)
  ~/.local/state/my-mac-bash-profile/       on/off + welcome counter

Environment:
  BASH_PROFILE_MOTD=0          never show at login (same as --off)
  BASH_PROFILE_MOTD_TIMES=N    how many shells show the welcome (default 3)
  BASH_PROFILE_MODULES_DISABLE="motd"   don't load this module at all

Exit codes:
  0 success
  1 runtime error
  2 usage/unknown option
USAGE
}

motd() {
    local action="show"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) _motd_usage; return 0 ;;
            --edit)    action="edit" ;;
            --off)     action="off" ;;
            --on)      action="on" ;;
            --) shift; break ;;
            *)
                echo "motd: unknown option: $1" >&2
                _motd_usage >&2
                return 2
                ;;
        esac
        shift
    done

    local config_file state_dir
    config_file="$(_motd_config_file)"
    state_dir="$(_motd_state_dir)"

    case "$action" in
        show)
            if [[ -r "$config_file" ]]; then
                _motd_print_file "$config_file"
            else
                _motd_welcome
            fi
            ;;
        edit)
            local editor="${VISUAL:-${EDITOR:-}}"
            if [[ -z "$editor" ]]; then
                local candidate
                for candidate in nano vi; do
                    if command -v "$candidate" >/dev/null 2>&1; then
                        editor="$candidate"
                        break
                    fi
                done
            fi
            if [[ -z "$editor" ]]; then
                echo "motd: no editor found; set EDITOR, or write the file yourself: $config_file" >&2
                return 1
            fi
            mkdir -p "${config_file%/*}" || return 1
            if [[ ! -e "$config_file" ]]; then
                {
                    echo "Hello, $(id -un 2>/dev/null || echo there)!"
                    echo "(Edit this file to change your login message: $config_file)"
                } > "$config_file" || return 1
            fi
            # $editor may carry flags (e.g. "code --wait"), so split it on purpose.
            # shellcheck disable=SC2086
            $editor "$config_file"
            ;;
        off)
            mkdir -p "$state_dir" || return 1
            : > "$state_dir/motd_off" || return 1
            echo "motd: off. Turn it back on with: motd --on"
            ;;
        on)
            rm -f "$state_dir/motd_off" "$state_dir/motd_count" || return 1
            echo "motd: on."
            ;;
    esac
}

# Show the message once per interactive shell session.
_motd_autoshow() {
    [[ $- == *i* ]] || return 0
    [[ "${BASH_PROFILE_MOTD:-1}" != "0" ]] || return 0
    # Nested shells inherit this, so `bash` inside a session stays quiet.
    [[ -z "${__MMBP_MOTD_SHOWN:-}" ]] || return 0
    export __MMBP_MOTD_SHOWN=1

    # Inline paths (no $(...)): this runs at every shell start.
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/my-mac-bash-profile/motd"
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/my-mac-bash-profile"
    [[ ! -e "$state_dir/motd_off" ]] || return 0

    if [[ -r "$config_file" ]]; then
        _motd_print_file "$config_file" >&2
        return 0
    fi

    local count=0 times="${BASH_PROFILE_MOTD_TIMES:-3}"
    [[ "$times" =~ ^[0-9]+$ ]] || times=3
    if [[ -r "$state_dir/motd_count" ]]; then
        read -r count < "$state_dir/motd_count" || true
        [[ "$count" =~ ^[0-9]+$ ]] || count=0
    fi
    [[ "$count" -lt "$times" ]] || return 0

    count=$((count + 1))
    # Count only if we can record it, so an unwritable HOME can't mean "forever".
    if [[ -d "$state_dir" ]] || mkdir -p "$state_dir" 2>/dev/null; then
        { printf '%s\n' "$count" > "$state_dir/motd_count"; } 2>/dev/null || return 0
    else
        return 0
    fi
    _motd_welcome "$count" >&2
}

_motd_autoshow
