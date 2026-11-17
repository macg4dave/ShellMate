#!/usr/bin/env bash
set -euo pipefail

# Install the tools ShellMate's helpers can use on Linux.
# - Installs only what's missing: a small core set, plus optional extras with --full.
# - --list prints the package manager and the missing packages, so
#   scripts/install.sh can ask before installing anything.
# - --dry-run prints the commands without running them.
# - ShellMate works without any of these; helpers show N/A instead.

usage() {
  cat <<'EOF'
Usage: scripts/bootstrap-linux.sh [--full] [--list] [--dry-run]

Install the tools ShellMate's helpers use (only the ones that are missing).

  --full     Also install optional extras (7-Zip, unrar, wireless-tools, iproute2)
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
    *) echo "bootstrap-linux.sh: unknown option: $1" >&2; usage >&2; exit 2 ;;
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

# Each entry is "package:command"; a package is skipped when its command exists.
pm=""
core=()
optional=()
if has apt-get; then
  pm=apt
  core=(curl:curl wget:wget unzip:unzip xz-utils:xz shellcheck:shellcheck)
  optional=(p7zip-full:7z unrar:unrar wireless-tools:iwgetid iproute2:ip)
elif has dnf || has yum; then
  if has dnf; then pm=dnf; else pm=yum; fi
  core=(curl:curl wget:wget unzip:unzip xz:xz ShellCheck:shellcheck)
  optional=(p7zip:7za p7zip-plugins:7z unrar:unrar wireless-tools:iwgetid iproute:ip)
elif has pacman; then
  pm=pacman
  core=(curl:curl wget:wget unzip:unzip xz:xz shellcheck:shellcheck)
  optional=(p7zip:7z unrar:unrar wireless_tools:iwgetid iproute2:ip)
elif has zypper; then
  pm=zypper
  core=(curl:curl wget:wget unzip:unzip xz:xz ShellCheck:shellcheck)
  optional=(p7zip:7z unrar:unrar wireless-tools:iwgetid iproute2:ip)
elif has apk; then
  pm=apk
  core=(curl:curl wget:wget unzip:unzip xz:xz shellcheck:shellcheck)
  optional=(p7zip:7z unrar:unrar wireless-tools:iwgetid iproute2:ip)
fi

missing_core=()
missing_optional=()
for e in ${core[@]+"${core[@]}"}; do
  has "${e#*:}" || missing_core+=("${e%%:*}")
done
for e in ${optional[@]+"${optional[@]}"}; do
  has "${e#*:}" || missing_optional+=("${e%%:*}")
done

if [[ "$list" -eq 1 ]]; then
  printf 'manager=%s\n' "$pm"
  printf 'core=%s\n' "${missing_core[*]:-}"
  printf 'optional=%s\n' "${missing_optional[*]:-}"
  exit 0
fi

if [[ -z "$pm" ]]; then
  echo "No supported package manager found (apt, dnf, yum, pacman, zypper, apk)." >&2
  echo "Install at least: curl wget" >&2
  exit 1
fi

as_root() {
  if [[ "$(id -u 2>/dev/null || echo 1)" == "0" ]]; then
    run "$@"
  elif has sudo || [[ "$dry_run" -eq 1 ]]; then
    run sudo "$@"
  else
    echo "Installing packages needs root, and sudo isn't available. Re-run as root." >&2
    return 1
  fi
}

refreshed=0
pm_install() {
  case "$pm" in
    apt)
      if [[ "$refreshed" -eq 0 ]]; then
        as_root apt-get update -qq || return 1
        refreshed=1
      fi
      as_root apt-get install -y -qq "$@"
      ;;
    dnf|yum) as_root "$pm" install -y -q "$@" ;;
    pacman)  as_root pacman -Sy --needed --noconfirm "$@" ;;
    zypper)  as_root zypper --non-interactive --quiet install "$@" ;;
    apk)     as_root apk add --quiet "$@" ;;
  esac
}

if [[ ${#missing_core[@]} -eq 0 ]]; then
  say "Recommended tools are already installed."
else
  say "Installing with $pm: ${missing_core[*]}"
  pm_install "${missing_core[@]}" || { echo "Could not install: ${missing_core[*]}" >&2; exit 1; }
fi

if [[ "$full" -eq 1 ]]; then
  if [[ ${#missing_optional[@]} -eq 0 ]]; then
    say "Optional extras are already installed."
  else
    say "Installing optional extras with $pm: ${missing_optional[*]}"
    if ! pm_install "${missing_optional[@]}"; then
      # Some extras (e.g. unrar) aren't in every distro's default repos;
      # install what we can, one at a time.
      unavailable=()
      for p in "${missing_optional[@]}"; do
        pm_install "$p" || unavailable+=("$p")
      done
      if [[ ${#unavailable[@]} -gt 0 ]]; then
        echo "Not available from $pm (skipped): ${unavailable[*]}" >&2
      fi
    fi
  fi
fi
