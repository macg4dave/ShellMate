#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Bash login profile (portable: macOS + Linux)
#
# This file is typically symlinked to ~/.bash_profile.
# It sources optional modules from ./profile.d/.
#------------------------------------------------------------------------------

# Resolve this file's directory even when ~/.bash_profile is a symlink.
__bp_source="${BASH_SOURCE[0]}"
while [[ -L "$__bp_source" ]]; do
	__bp_dir="$(cd -P -- "$(dirname "$__bp_source")" && pwd)"
	__bp_link="$(readlink "$__bp_source" 2>/dev/null)" || break
	[[ "$__bp_link" != /* ]] && __bp_link="$__bp_dir/$__bp_link"
	__bp_source="$__bp_link"
done
__bp_root="$(cd -P -- "$(dirname "$__bp_source")" && pwd)"

__bp_profile_d="$__bp_root/profile.d"

#------------------------------------------------------------------------------
# Surpess bash deprecation warning on macOS
#------------------------------------------------------------------------------

export BASH_SILENCE_DEPRECATION_WARNING=1

#------------------------------------------------------------------------------
# Module loader configuration
#
# - By default, all modules in profile.d/ are loaded.
# - You can disable modules without editing this repo by setting:
#     BASH_PROFILE_MODULES_DISABLE="netinfo sysinfo"   (names or filenames)
# - You can allowlist modules (load only these) with:
#     BASH_PROFILE_MODULES_ENABLE="extract netinfo"
# - Lists may be space- or comma-separated. Entries may be either:
#     netinfo    OR    netinfo.sh
#
# Local overrides are sourced last (if present):
#   1) <repo>/profile.d/local.sh                (recommended; gitignored)
#   2) ${XDG_CONFIG_HOME:-~/.config}/my-mac-bash-profile/local.sh
#------------------------------------------------------------------------------

__bp_modules_enable="${BASH_PROFILE_MODULES_ENABLE:-}"
__bp_modules_disable="${BASH_PROFILE_MODULES_DISABLE:-}"

# Shared warning helpers for modules; may have no callers, which ShellCheck
# reports as SC2317 (<=0.10) or SC2329 (>=0.11).
# shellcheck disable=SC2317,SC2329
__bp_is_interactive() {
	[[ $- == *i* ]]
}

# shellcheck disable=SC2317,SC2329
__bp_warn() {
	# Warnings must be interactive-only to avoid breaking scripts.
	__bp_is_interactive || return 0
	printf '%s\n' "$*" >&2
}

#------------------------------------------------------------------------------
# Load guard: a mistake in a module or local override must not cost the user
# their terminal. While each file loads:
#   - `exit` / `logout` are ignored (with a warning): they would close the
#     terminal the moment it opens;
#   - `set -e` / `set -o errexit` is dropped (with a warning): afterwards any
#     failing command would close the terminal.
# Files are still sourced at top level (not inside a function), so their
# `declare` / `local` behave exactly as before.
#------------------------------------------------------------------------------

# shellcheck disable=SC2317,SC2329
__bp_guard_set() {
	local __bp_i=1 __bp_a __bp_next __bp_dropped=0
	local __bp_out=()
	while [[ "$__bp_i" -le $# ]]; do
		__bp_a="${!__bp_i}"
		case "$__bp_a" in
			-|--|[!-+]*)
				# Setting positional parameters can't work through a wrapper
				# function (it would only set the wrapper's own), so say so
				# rather than silently doing nothing.
				__bp_warn "shellmate: 'set -- ...' isn't supported in ${__bp_guard_file:-startup files}; use an array instead"
				break
				;;
			-o)
				__bp_next=$((__bp_i + 1))
				if [[ "${!__bp_next:-}" == "errexit" ]]; then
					__bp_dropped=1
					__bp_i=$((__bp_i + 2))
					continue
				fi
				;;
			-*e*)
				# Short-option cluster such as -e or -euo: drop just the e.
				__bp_dropped=1
				__bp_a="${__bp_a//e/}"
				if [[ "$__bp_a" == "-" ]]; then
					__bp_i=$((__bp_i + 1))
					continue
				fi
				;;
		esac
		__bp_out+=("$__bp_a")
		__bp_i=$((__bp_i + 1))
	done
	if [[ "$__bp_dropped" -eq 1 ]]; then
		__bp_warn "shellmate: ignored 'set -e' in ${__bp_guard_file:-a startup file} (one failing command would close your terminal)"
	fi
	# Plain `set` with no arguments would print every variable; don't.
	[[ ${#__bp_out[@]} -gt 0 ]] || return 0
	builtin set "${__bp_out[@]}"
}

# shellcheck disable=SC2317,SC2329
__bp_guard_on() {
	__bp_guard_file="$1"
	__bp_guard_defined=""
	__bp_guard_errexit=0
	[[ $- == *e* ]] && __bp_guard_errexit=1
	# Never replace a function the user defined themselves.
	if ! declare -F exit >/dev/null 2>&1; then
		exit() { __bp_warn "shellmate: ignored 'exit' in ${__bp_guard_file} (it would close your terminal)"; return 0; }
		__bp_guard_defined+=" exit"
	fi
	if ! declare -F logout >/dev/null 2>&1; then
		logout() { __bp_warn "shellmate: ignored 'logout' in ${__bp_guard_file} (it would close your terminal)"; return 0; }
		__bp_guard_defined+=" logout"
	fi
	if ! declare -F set >/dev/null 2>&1; then
		set() { __bp_guard_set "$@"; }
		__bp_guard_defined+=" set"
	fi
}

# shellcheck disable=SC2317,SC2329
__bp_guard_off() {
	local __bp_fn
	for __bp_fn in $__bp_guard_defined; do
		unset -f "$__bp_fn"
	done
	# Belt and braces: if errexit got switched on anyway (e.g. via shopt), undo it.
	if [[ $- == *e* && "$__bp_guard_errexit" -eq 0 ]]; then
		builtin set +e
		__bp_warn "shellmate: turned 'set -e' back off after ${__bp_guard_file} (it would close your terminal on any error)"
	fi
	unset __bp_guard_file __bp_guard_defined __bp_guard_errexit
}

__bp_list_contains_any() {
	# Usage: __bp_list_contains_any "list" candidate1 [candidate2 ...]
	local list="$1"
	shift
	local token candidate
	list="${list//,/ }"
	for token in $list; do
		for candidate in "$@"; do
			[[ "$token" == "$candidate" ]] && return 0
		done
	done
	return 1
}

__bp_should_source_module() {
	local path="$1"
	local base stem
	base="$(basename "$path")"
	stem="${base%.sh}"

	# Local overrides are handled explicitly at the end.
	[[ "$base" == "local.sh" ]] && return 1

	if [[ -n "$__bp_modules_enable" ]]; then
		__bp_list_contains_any "$__bp_modules_enable" "$stem" "$base" || return 1
	fi
	if [[ -n "$__bp_modules_disable" ]]; then
		__bp_list_contains_any "$__bp_modules_disable" "$stem" "$base" && return 1
	fi
	return 0
}

# Source common helpers first (defines has_cmd + IS_MAC/IS_LINUX + PATH helpers).
if [[ -r "$__bp_profile_d/10-common.sh" ]]; then
	__bp_guard_on "$__bp_profile_d/10-common.sh"
	# shellcheck source=/dev/null
	source "$__bp_profile_d/10-common.sh"
	__bp_guard_off
fi

# Aliases, prompt and PATH need IS_MAC + path_prepend_if_exists from
# 10-common.sh, so they must come after it (and before other modules, so
# modules and local overrides can still change them).
#------------------------------------------------------------------------------
## Aliases and environment variables
# Common convenience aliases and environment variable exports.
# Easy to remember aliases for common commands.
#------------------------------------------------------------------------------

if [[ "${IS_MAC:-false}" == "true" ]]; then
	alias ls='ls -GFhla'
else
	# GNU ls: keep similar UX.
	alias ls='ls --color=auto -Fhla'
fi


#------------------------------------------------------------------------------
## Export PATHS
# Common PATH exports and hygiene.
#------------------------------------------------------------------------------

if [[ "${BASH_PROFILE_SET_PS1:-1}" != "0" ]]; then
	export PS1="\[\e[36;40m\]\u\[\e[m\]\[\e[35m\]@\[\e[m\][\[\e[33m\]\h\[\e[m\]]\[\e[36m\]\w\[\e[m\]: "
fi

# macOS color env is harmless elsewhere, but only set when on macOS.
if [[ "${IS_MAC:-false}" == "true" ]]; then
	export CLICOLOR=1
	export LSCOLORS=ExFxBxDxCxegedabagacad
	export BASH_SILENCE_DEPRECATION_WARNING=1
fi

# PATH hygiene: only prepend directories that exist.
if declare -F path_prepend_if_exists >/dev/null 2>&1; then
	path_prepend_if_exists "/usr/local/sbin"
	path_prepend_if_exists "/opt/local/bin"
	path_prepend_if_exists "/opt/local/sbin"
	path_prepend_if_exists "/usr/local/opt/curl/bin"
	path_prepend_if_exists "/usr/local/opt/cython/bin"
else
	# 10-common.sh missing: same rule, inline.
	for __bp_f in /usr/local/sbin /opt/local/bin /opt/local/sbin; do
		[[ -d "$__bp_f" ]] && PATH="$__bp_f:$PATH"
	done
	export PATH
fi


#------------------------------------------------------------------------------
# Load remaining modules (if present).
#
# Recovery: BASH_PROFILE_SAFE_MODE=1 skips all modules and local overrides,
# e.g. `BASH_PROFILE_SAFE_MODE=1 bash -l` (or as your terminal's command).
#------------------------------------------------------------------------------
if [[ "${BASH_PROFILE_SAFE_MODE:-0}" == "1" ]]; then
	__bp_warn "shellmate: safe mode - modules and local overrides not loaded (unset BASH_PROFILE_SAFE_MODE to leave it)"
elif [[ -d "$__bp_profile_d" ]]; then
	__bp_nullglob_was_set=0
	shopt -q nullglob && __bp_nullglob_was_set=1
	shopt -s nullglob

	# Plugin-friendly mode: if unnumbered modules exist, prefer those.
	# Backward-compatible mode: otherwise load legacy numbered modules.
	__bp_has_unnumbered=0
	for __bp_f in "$__bp_profile_d"/*.sh; do
		[[ -r "$__bp_f" ]] || continue
		case "$__bp_f" in
			"$__bp_profile_d"/[0-9][0-9]-*.sh) continue ;;
		esac
		__bp_has_unnumbered=1
		break
	done

	if [[ "$__bp_has_unnumbered" -eq 1 ]]; then
		for __bp_f in "$__bp_profile_d"/*.sh; do
			[[ -r "$__bp_f" ]] || continue
			case "$__bp_f" in
				"$__bp_profile_d"/[0-9][0-9]-*.sh) continue ;;
			esac
			__bp_should_source_module "$__bp_f" || continue
			__bp_guard_on "$__bp_f"
			# shellcheck source=/dev/null
			source "$__bp_f"
			__bp_guard_off
		done
	else
		for __bp_f in "$__bp_profile_d"/[0-9][0-9]-*.sh; do
			[[ -r "$__bp_f" ]] || continue
			[[ "$__bp_f" == "$__bp_profile_d/10-common.sh" ]] && continue
			__bp_should_source_module "$__bp_f" || continue
			__bp_guard_on "$__bp_f"
			# shellcheck source=/dev/null
			source "$__bp_f"
			__bp_guard_off
		done
	fi
	unset __bp_has_unnumbered

	# Local override modules (sourced last).
	if [[ -r "$__bp_profile_d/local.sh" ]]; then
		__bp_guard_on "$__bp_profile_d/local.sh"
		# shellcheck source=/dev/null
		source "$__bp_profile_d/local.sh"
		__bp_guard_off
	fi
	__bp_xdg_local="${XDG_CONFIG_HOME:-$HOME/.config}/my-mac-bash-profile/local.sh"
	if [[ -r "$__bp_xdg_local" ]]; then
		__bp_guard_on "$__bp_xdg_local"
		# shellcheck source=/dev/null
		source "$__bp_xdg_local"
		__bp_guard_off
	fi
	unset __bp_xdg_local

	if [[ "$__bp_nullglob_was_set" -eq 1 ]]; then
		shopt -s nullglob
	else
		shopt -u nullglob
	fi
	unset __bp_nullglob_was_set
fi

unset __bp_source __bp_dir __bp_link __bp_root __bp_profile_d __bp_f __bp_modules_enable __bp_modules_disable
unset -f __bp_list_contains_any __bp_should_source_module __bp_is_interactive __bp_warn \
	__bp_guard_set __bp_guard_on __bp_guard_off 2>/dev/null || true

#-----------------------------------
## END
#-----------------------------------

