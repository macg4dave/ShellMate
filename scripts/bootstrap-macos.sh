#!/usr/bin/env bash
set -euo pipefail

# Install the tools ShellMate's helpers can use on macOS, via Homebrew.
# - Installs only what's missing: a small core set, plus optional extras with --full.
# - --list prints the package manager and the missing packages, so
#   scripts/install.sh can ask before installing anything.
# - --dry-run prints the commands without running them.
# - ShellMate works without any of these; helpers show N/A instead.

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-macos.sh [--full] [--list] [--dry-run]

Install the tools ShellMate's helpers use with Homebrew (only the ones that are missing).

  --full     Also install optional extras (p7zip, for more archive formats in extract)
  --list     Print the package manager and the missing packages, then exit
  --dry-run  Print the install commands without running them
EOF
}

full=0
dry_run=0
list=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --full) full=1 ;;
    --list) list=1 ;;
    --dry-run|-n) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "bootstrap-macos.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

say() { printf '  %s\n' "$*"; }
has() { command -v "$1" >/dev/null 2>&1; }

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    local q=() a
    for a in "$@"; do
      q+=("$(printf '%q' "$a")")
    done
    printf '    $ %s\n' "${q[*]}"
  else
    "$@"
  fi
}

if [[ "$(uname -s 2>/dev/null)" != "Darwin" ]]; then
  echo "This script is for macOS (Darwin)." >&2
  exit 1
fi

# Each entry is "package:command"; a package is skipped when its command exists.
# - shellcheck: linting
# - coreutils: gnumfmt (sysinfo uses numfmt-style sizes when available)
# - wget: netinfo external IP fallback
# - p7zip: more archive formats in extract
core=(shellcheck:shellcheck coreutils:gnumfmt wget:wget)
optional=(p7zip:7z)

missing_core=()
missing_optional=()
for e in "${core[@]}"; do
  has "${e#*:}" || missing_core+=("${e%%:*}")
done
for e in "${optional[@]}"; do
  has "${e#*:}" || missing_optional+=("${e%%:*}")
done

pm=""
has brew && pm=brew

if [[ "$list" -eq 1 ]]; then
  printf 'manager=%s\n' "$pm"
  printf 'core=%s\n' "${missing_core[*]:-}"
  printf 'optional=%s\n' "${missing_optional[*]:-}"
  exit 0
fi

if [[ -z "$pm" ]]; then
  echo "Homebrew not found. Install it from https://brew.sh/ and re-run." >&2
  exit 1
fi

to_install=(${missing_core[@]+"${missing_core[@]}"})
if [[ "$full" -eq 1 ]]; then
  to_install+=(${missing_optional[@]+"${missing_optional[@]}"})
fi

if [[ ${#to_install[@]} -eq 0 ]]; then
  say "Recommended tools are already installed."
  exit 0
fi

say "Installing with Homebrew: ${to_install[*]}"
run brew update
run brew install "${to_install[@]}"
