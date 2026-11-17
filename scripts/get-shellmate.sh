#!/usr/bin/env bash
# ShellMate online installer (published with each release as shellmate-install.sh).
#
#   curl -fsSL https://github.com/macg4dave/ShellMate/releases/latest/download/shellmate-install.sh | bash
#
# Options after `bash -s --` are passed to scripts/install.sh, e.g.:
#   ... | bash -s -- --yes                  # don't ask before replacing ~/.bash_profile
#   ... | bash -s -- --bootstrap auto       # also install optional tools (uses sudo/brew)
#   ... | bash -s -- --dry-run              # show what would change
#
# Environment:
#   SHELLMATE_VERSION=v3.0.0   install a specific release (default: latest)
#
# What it does: downloads the release tarball + SHA256SUMS over HTTPS, checks
# the checksum, unpacks to a temp dir and runs the bundled scripts/install.sh
# (which backs up anything it replaces). Nothing is installed system-wide.

# Everything lives in main(), called on the last line, so a partially
# downloaded script can never run half-way.

set -euo pipefail

SHELLMATE_REPO="macg4dave/ShellMate"

_say() { printf 'shellmate-install: %s\n' "$*"; }
_die() { printf 'shellmate-install: error: %s\n' "$*" >&2; exit 1; }
_has() { command -v "$1" >/dev/null 2>&1; }

# Usage: _fetch <url> <dest-file>
_fetch() {
  local url="$1" dest="$2"
  if _has curl; then
    if [[ "$url" == https://* ]]; then
      curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$dest"
    else
      curl -fsSL "$url" -o "$dest"   # file:// in tests
    fi
  elif _has wget; then
    wget -q -O "$dest" "$url"
  else
    _die "need curl or wget to download ShellMate"
  fi
}

_latest_version() {
  local api="https://api.github.com/repos/${SHELLMATE_REPO}/releases/latest" json tag
  json="$(mktemp)"
  _fetch "$api" "$json" || { rm -f "$json"; _die "could not look up the latest release ($api)"; }
  tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$json" | head -n 1)"
  rm -f "$json"
  [[ -n "$tag" ]] || _die "could not read the latest release tag; set SHELLMATE_VERSION=vX.Y.Z"
  printf '%s\n' "$tag"
}

_sha256() {
  if _has sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  elif _has shasum; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

main() {
  [[ -n "${BASH_VERSION:-}" ]] || _die "please run with bash: curl ... | bash"
  _has tar || _die "need tar to unpack ShellMate"
  [[ -n "${HOME:-}" ]] || _die "HOME is not set"

  local version="${SHELLMATE_VERSION:-}"
  [[ -n "$version" ]] || version="$(_latest_version)"
  [[ "$version" == v* ]] || version="v$version"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || _die "bad version '$version' (expected vX.Y.Z)"

  # SHELLMATE_DOWNLOAD_BASE is for tests (e.g. file:///path/to/dist).
  local base="${SHELLMATE_DOWNLOAD_BASE:-https://github.com/${SHELLMATE_REPO}/releases/download/${version}}"
  local name="shellmate-${version#v}"

  local tmp
  tmp="$(mktemp -d 2>/dev/null || mktemp -d -t shellmate)"
  # shellcheck disable=SC2064  # expand $tmp now, on purpose
  trap "rm -rf '$tmp'" EXIT

  _say "downloading ShellMate ${version}"
  _fetch "$base/${name}.tar.gz" "$tmp/${name}.tar.gz" || _die "download failed: $base/${name}.tar.gz"
  _fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS" || _die "download failed: $base/SHA256SUMS"

  local want got
  want="$(awk -v f="${name}.tar.gz" '$2 == f || $2 == "*"f {print $1; exit}' "$tmp/SHA256SUMS")"
  [[ -n "$want" ]] || _die "SHA256SUMS has no entry for ${name}.tar.gz"
  if got="$(_sha256 "$tmp/${name}.tar.gz")"; then
    [[ "$got" == "$want" ]] || _die "checksum mismatch for ${name}.tar.gz (expected $want, got $got)"
    _say "checksum ok"
  else
    _say "warning: no sha256sum/shasum found; skipping checksum check" >&2
  fi

  tar -xzf "$tmp/${name}.tar.gz" -C "$tmp"
  [[ -f "$tmp/$name/scripts/install.sh" ]] || _die "release archive is missing scripts/install.sh"

  # Optional dependency installs use sudo/brew; only when asked for.
  local args=("$@") has_bootstrap=0 a
  for a in ${args[@]+"${args[@]}"}; do
    [[ "$a" == "--bootstrap" ]] && has_bootstrap=1
  done
  [[ "$has_bootstrap" -eq 1 ]] || args+=(--bootstrap none)

  # When piped (`curl | bash`) stdin is this script, so let the installer ask
  # its questions on the terminal instead.
  if [[ ! -t 0 ]] && (exec </dev/tty) 2>/dev/null; then
    bash "$tmp/$name/scripts/install.sh" --repo "$tmp/$name" "${args[@]}" </dev/tty
  else
    bash "$tmp/$name/scripts/install.sh" --repo "$tmp/$name" "${args[@]}"
  fi

  _say "done. Open a new terminal (or run: source ~/.bash_profile) to start using ShellMate ${version}."
}

main "$@"
