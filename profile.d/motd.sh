#------------------------------------------------------------------------------
# motd: message of the day for interactive shells
#
# - First BASH_PROFILE_MOTD_TIMES (default 3) interactive shells: a short
#   ShellMate welcome with basic usage, then it stops by itself.
# - Your own message (motd --edit) is shown at every interactive shell instead.
# - motd --off / --on turns the automatic message off / back on.
#
# Safe to source: does nothing unless the shell is interactive; prints to
# stderr only; starts no processes once the welcome has run its course (a
# custom message may run `tput cols` once if COLUMNS is unset); the
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

# Your message file: lines starting with "#" are notes to yourself and are
# never shown. A file with only notes/blank lines counts as "no message", so
# saving the starter file from `motd --edit` untouched keeps the welcome.
# Usage: _motd_read_message <file>  -- sets _MOTD_MSG (array of shown lines).
#
# The file is only ever printed, never run, and it's cleaned up first so a
# bad paste can't hurt the terminal: control characters (escape sequences
# that clear the screen or switch charsets, Windows \r) are removed, tabs
# become spaces, lines are capped at 200 characters and the message at 40
# lines (reading stops after 400), so login stays fast whatever is in it.
_motd_read_message() {
    _MOTD_MSG=()
    local line has_text=0 read_count=0
    [[ -f "$1" && -r "$1" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        read_count=$((read_count + 1))
        [[ "$read_count" -le 400 && ${#_MOTD_MSG[@]} -lt 40 ]] || break
        [[ "$line" == "#"* ]] && continue
        line="${line//$'\t'/    }"
        line="${line//[[:cntrl:]]/}"
        [[ ${#line} -le 200 ]] || line="${line:0:197}..."
        if [[ "$line" =~ [^[:space:]] ]]; then
            has_text=1
        elif [[ "$has_text" -eq 0 ]]; then
            continue   # skip blank lines before the first real line
        fi
        _MOTD_MSG+=("$line")
    done < "$1"
    # ...and after the last one.
    while [[ ${#_MOTD_MSG[@]} -gt 0 && ! "${_MOTD_MSG[${#_MOTD_MSG[@]} - 1]}" =~ [^[:space:]] ]]; do
        unset "_MOTD_MSG[${#_MOTD_MSG[@]} - 1]"
    done
    [[ "$has_text" -eq 1 ]]
}

# Starter file written by `motd --edit` (all notes, so it shows nothing yet).
_motd_starter() {
    cat <<EOF
# Your ShellMate login message
# ============================
# Write your message below these notes; it replaces the ShellMate welcome and
# shows every time a terminal opens. Lines starting with # are never shown.
#
# Changed your mind?
#   - Leave only # lines (or delete this file) to get the ShellMate welcome back:
#       rm $1
#   - Turn the login message off completely:   motd --off
#   - Turn it back on:                         motd --on
#   - See what it looks like now:              motd
#
# Example (remove the leading "# " to use it):
# Hello, ${2:-there}! Backups run nightly at 02:00.

EOF
}

#------------------------------------------------------------------------------
# Rendering. Same approach as sysinfo's box (UTF-8 box chars with an ASCII
# fallback, 256- and 8-colour palettes) but with raw SGR codes instead of
# `tput`, so showing a message at login starts no extra processes.
#------------------------------------------------------------------------------

# command|how to call it|what it does
_MOTD_CMDS=(
'sysinfo||OS, uptime, CPU load, memory, disk and network totals'
'netinfo||Hostname, local and public IP, gateway and VPN status'
'extract|<file>|Unpack tar, zip, 7z, rar, gz and more into a folder'
'pathinfo||List your PATH and flag duplicate or missing folders'
'flushdns||Clear the DNS cache when websites stop resolving'
'jd|<url>|Download a file with wget, resuming if interrupted'
)
_MOTD_CMD_W=16   # width of the command column

# Usage: _motd_style <fd>  -- sets colours + box characters for output on <fd>.
_motd_style() {
    local fd="$1" level=0
    _MOTD_R="" _MOTD_BORDER="" _MOTD_BG="" _MOTD_BG1="" _MOTD_BG2=""
    _MOTD_HEAD="" _MOTD_TAG="" _MOTD_CMD="" _MOTD_ARG="" _MOTD_DESC="" _MOTD_MUTED=""

    if [[ -t "$fd" && -z "${NO_COLOR:-}" ]]; then
        case "${TERM:-dumb}" in
            dumb|"") level=0 ;;
            *256color*|*-kitty|alacritty|wezterm|foot*|tmux*|screen*) level=256 ;;
            *) level=8 ;;
        esac
        case "${COLORTERM:-}" in truecolor|24bit) [[ "$level" -gt 0 ]] && level=256 ;; esac
    fi

    local e=$'\033['
    if [[ "$level" -eq 256 ]]; then
        _MOTD_R="${e}0m"
        _MOTD_BORDER="${e}38;5;67m"     # steel blue
        _MOTD_BG1="${e}48;5;236m"       # command rows alternate between two
        _MOTD_BG2="${e}48;5;235m"       # dark greys, like sysinfo --box
        _MOTD_HEAD="${e}1;38;5;220m"    # yellow: title
        _MOTD_TAG="${e}38;5;75m"        # blue: tagline
        _MOTD_CMD="${e}1;38;5;221m"     # yellow: anything you type
        _MOTD_ARG="${e}38;5;186m"       # softer yellow: what you type after it
        _MOTD_DESC="${e}38;5;111m"      # blue: what it does / how to use it
        _MOTD_MUTED="${e}38;5;244m"     # grey: counter
    elif [[ "$level" -eq 8 ]]; then
        _MOTD_R="${e}0m"
        _MOTD_BORDER="${e}34m"
        # No row stripes: 8 colours has no grey subtle enough to read on.
        _MOTD_HEAD="${e}1;33m"
        _MOTD_TAG="${e}94m"
        _MOTD_CMD="${e}1;33m"
        _MOTD_ARG="${e}33m"
        _MOTD_DESC="${e}94m"
        _MOTD_MUTED="${e}2m"
    fi

    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$loc" =~ [Uu][Tt][Ff]-?8 ]]; then
        _MOTD_TL="╭" _MOTD_TR="╮" _MOTD_BL="╰" _MOTD_BR="╯" _MOTD_H="─" _MOTD_V="│" _MOTD_ML="├" _MOTD_MR="┤"
    else
        _MOTD_TL="+" _MOTD_TR="+" _MOTD_BL="+" _MOTD_BR="+" _MOTD_H="-" _MOTD_V="|" _MOTD_ML="+" _MOTD_MR="+"
    fi
}

_motd_cols() {
    local cols="${COLUMNS:-}"
    if [[ ! "$cols" =~ ^[0-9]+$ ]] && command -v tput >/dev/null 2>&1; then
        cols="$(tput cols 2>/dev/null || true)"
    fi
    [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 0 ]] || cols=80
    printf '%s\n' "$cols"
}

_motd_rep() {
    local out="" i
    for ((i = 0; i < $2; i++)); do out+="$1"; done
    printf '%s' "$out"
}

# Line builder: append coloured text while tracking its visible width.
# Everything appended (padding too) gets the current row background $_MOTD_BG.
_motd_seg() {
    if [[ -n "$1$_MOTD_BG" ]]; then
        _MOTD_LINE+="$_MOTD_BG$1$2$_MOTD_R"
    else
        _MOTD_LINE+="$2"
    fi
    _MOTD_LEN=$((_MOTD_LEN + ${#2}))
}
_motd_pad_to() {
    [[ "$_MOTD_LEN" -lt "$1" ]] || return 0
    local pad="" i
    for ((i = _MOTD_LEN; i < $1; i++)); do pad+=" "; done   # no subshell: runs at login
    _motd_seg "" "$pad"
}
# Usage: _motd_emit <inner_width>  -- print the built line inside the box.
_motd_emit() {
    _motd_pad_to "$1"
    printf '%s%s%s%s%s%s%s\n' "$_MOTD_BORDER" "$_MOTD_V" "$_MOTD_R" "$_MOTD_LINE" "$_MOTD_BORDER" "$_MOTD_V" "$_MOTD_R"
    _MOTD_LINE="" _MOTD_LEN=0
}
_motd_top() {
    _motd_rule "$_MOTD_TL" "$1" "$_MOTD_TR"
}
# Usage: _motd_title_box <inner_width>  -- "Welcome" + tagline in their own box.
_motd_title_box() {
    _motd_top "$1"
    _motd_seg "" " "
    _motd_seg "$_MOTD_HEAD" "Welcome to ShellMate"
    _motd_emit "$1"
    _motd_seg "" " "
    _motd_seg "$_MOTD_TAG" "$_MOTD_TAGLINE"
    _motd_emit "$1"
    _motd_rule "$_MOTD_BL" "$1" "$_MOTD_BR"
}
_motd_rule() {
    printf '%s%s%s%s%s\n' "$_MOTD_BORDER" "$1" "$(_motd_rep "$_MOTD_H" "$2")" "$3" "$_MOTD_R"
}

_MOTD_TAGLINE="It's your shell, Mate!"
_MOTD_HELP_TXT=" to any command to see all of its options."
_MOTD_EDIT_TXT="  write your own login message"
_MOTD_OFF_TXT="  stop showing this at login"

# Usage: _motd_wrap <width> <text>  -- word-wrap into _MOTD_WRAP (array).
_motd_wrap() {
    local width="$1" word line=""
    _MOTD_WRAP=()
    # Split on spaces on purpose; the text is ours and has no glob characters.
    # shellcheck disable=SC2086
    for word in $2; do
        if [[ -z "$line" ]]; then
            line="$word"
        elif [[ $((${#line} + 1 + ${#word})) -le "$width" ]]; then
            line+=" $word"
        else
            _MOTD_WRAP+=("$line")
            line="$word"
        fi
    done
    [[ -n "$line" ]] && _MOTD_WRAP+=("$line")
    return 0
}

# Usage: _motd_welcome <fd> [shown_count]
_motd_welcome() {
    local fd="$1" shown="${2:-}" times cols
    times="$(_motd_times)"
    _motd_style "$fd"
    cols="$(_motd_cols)"
    _MOTD_LINE="" _MOTD_LEN=0 _MOTD_BG=""

    local counter=""
    [[ -n "$shown" ]] && counter="$shown of $times"

    local entry cmd rest arg desc
    if [[ "${TERM:-}" == "dumb" || "$cols" -lt 45 ]]; then   # narrowest box that fits the footer
        # Plain: no box, no colour.
        printf 'Welcome to ShellMate - %s\n\n' "$_MOTD_TAGLINE"
        for entry in "${_MOTD_CMDS[@]}"; do
            cmd="${entry%%|*}" rest="${entry#*|}"
            arg="${rest%%|*}"
            printf '  %-16s%s\n' "$cmd${arg:+ $arg}" "${rest#*|}"
        done
        printf '\nAdd --help%s\n' "$_MOTD_HELP_TXT"
        printf 'motd --edit: write your own login message   motd --off: stop showing this at login%s\n' \
            "${counter:+   ($counter)}"
        return 0
    fi

    # The box is as wide as the longest command row. When the terminal is
    # narrower, each description goes on its own (wrapped) line instead.
    local widest=0
    for entry in "${_MOTD_CMDS[@]}"; do
        rest="${entry#*|}" desc="${rest#*|}"
        [[ "${#desc}" -gt "$widest" ]] && widest="${#desc}"
    done
    local inner=$((1 + _MOTD_CMD_W + widest + 2)) stacked=0
    if [[ $((inner + 2)) -gt "$cols" ]]; then
        stacked=1
        inner=$((cols - 2))
    fi

    _motd_title_box "$inner"
    _motd_top "$inner"
    local i=0 line
    for entry in "${_MOTD_CMDS[@]}"; do
        cmd="${entry%%|*}" rest="${entry#*|}"
        arg="${rest%%|*}" desc="${rest#*|}"
        if (( i % 2 == 0 )); then _MOTD_BG="$_MOTD_BG1"; else _MOTD_BG="$_MOTD_BG2"; fi
        _motd_seg "" " "
        _motd_seg "$_MOTD_CMD" "$cmd"
        [[ -n "$arg" ]] && _motd_seg "$_MOTD_ARG" " $arg"
        if [[ "$stacked" -eq 0 ]]; then
            _motd_pad_to $((1 + _MOTD_CMD_W))
            _motd_seg "$_MOTD_DESC" "$desc"
            _motd_emit "$inner"
        else
            _motd_emit "$inner"
            _motd_wrap $((inner - 5)) "$desc"
            for line in "${_MOTD_WRAP[@]}"; do
                _motd_seg "" "    "
                _motd_seg "$_MOTD_DESC" "$line"
                _motd_emit "$inner"
            done
        fi
        i=$((i + 1))
    done
    _MOTD_BG=""
    _motd_rule "$_MOTD_ML" "$inner" "$_MOTD_MR"

    _motd_seg "" " "
    _motd_seg "$_MOTD_DESC" "Add "
    _motd_seg "$_MOTD_CMD" "--help"
    if [[ $((_MOTD_LEN + ${#_MOTD_HELP_TXT} + 1)) -le "$inner" ]]; then
        _motd_seg "$_MOTD_DESC" "$_MOTD_HELP_TXT"
    else
        _motd_seg "$_MOTD_DESC" "${_MOTD_HELP_TXT%% to see*}"
        _motd_emit "$inner"
        _motd_seg "" " "
        _motd_seg "$_MOTD_DESC" "to see${_MOTD_HELP_TXT#* to see}"
    fi
    if [[ -n "$counter" ]]; then
        # Right-align the counter; give it its own row if it doesn't fit.
        if [[ $((_MOTD_LEN + 2 + ${#counter})) -gt "$inner" ]]; then
            _motd_emit "$inner"
        fi
        _motd_pad_to $((inner - 1 - ${#counter}))
        _motd_seg "$_MOTD_MUTED" "$counter"
    fi
    _motd_emit "$inner"

    _motd_seg "" " "
    _motd_seg "$_MOTD_CMD" "motd --edit"
    _motd_seg "$_MOTD_DESC" "$_MOTD_EDIT_TXT"
    if [[ $((1 + 11 + ${#_MOTD_EDIT_TXT} + 3 + 10 + ${#_MOTD_OFF_TXT} + 1)) -le "$inner" ]]; then
        _motd_seg "" "   "
    else
        _motd_emit "$inner"
        _motd_seg "" " "
    fi
    local off_start="$_MOTD_LEN"
    _motd_seg "$_MOTD_CMD" "motd --off"
    [[ "$off_start" -eq 1 ]] && _motd_pad_to 12   # line up under "motd --edit"
    _motd_seg "$_MOTD_DESC" "$_MOTD_OFF_TXT"
    _motd_emit "$inner"
    _motd_rule "$_MOTD_BL" "$inner" "$_MOTD_BR"
}

# Usage: _motd_custom <fd> <file>  -- the user's own message, in the same frame.
_motd_custom() {
    local fd="$1" file="$2" cols line max=0
    _motd_read_message "$file" || return 0
    local lines=(${_MOTD_MSG[@]+"${_MOTD_MSG[@]}"})
    for line in ${lines[@]+"${lines[@]}"}; do
        [[ "${#line}" -gt "$max" ]] && max="${#line}"
    done

    _motd_style "$fd"
    cols="$(_motd_cols)"
    local inner=$((max + 4))
    [[ "$inner" -ge 30 ]] || inner=30
    if [[ "${TERM:-}" == "dumb" || $((inner + 2)) -gt "$cols" ]]; then
        [[ ${#lines[@]} -gt 0 ]] && printf '%s\n' "${lines[@]}"
        return 0
    fi

    _MOTD_LINE="" _MOTD_LEN=0
    _motd_top "$inner"
    for line in ${lines[@]+"${lines[@]}"}; do
        _motd_seg "" "  "
        _motd_seg "$_MOTD_DESC" "$line"
        _motd_emit "$inner"
    done
    _motd_rule "$_MOTD_BL" "$inner" "$_MOTD_BR"
}

_motd_usage() {
    cat <<'USAGE'
Usage: motd [--help] [--edit] [--off] [--on]

Show the message of the day. With no options, print it now.

Options:
  -h, --help   Show this help and exit.
  --edit       Edit your own message in $VISUAL / $EDITOR (shown at every login).
               Lines starting with # are ignored; leave only # lines, or
               delete the file, to go back to the ShellMate welcome.
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
            if _motd_read_message "$config_file"; then
                _motd_custom 1 "$config_file"
            else
                _motd_welcome 1
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
                local shown_path="${config_file/#$HOME/\~}"   # ~/... reads nicer in the notes
                _motd_starter "$shown_path" "$(id -un 2>/dev/null || true)" > "$config_file" || return 1
            fi
            # $editor may carry flags (e.g. "code --wait"), so split it on purpose.
            # shellcheck disable=SC2086
            $editor "$config_file" || return 1
            if _motd_read_message "$config_file"; then
                echo "motd: saved. It shows when a terminal opens (motd --off to stop it)."
            else
                echo "motd: no message written (only # lines), so the ShellMate welcome shows instead."
            fi
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

    if _motd_read_message "$config_file"; then
        _motd_custom 2 "$config_file" >&2
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
    _motd_welcome 2 "$count" >&2
}

_motd_autoshow
