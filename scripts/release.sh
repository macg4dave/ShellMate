#!/usr/bin/env bash
# Build ShellMate release files.
#
#   scripts/release.sh v3.0.0 [out_dir]      (default out_dir: dist)
#
# Produces in out_dir:
#   shellmate-X.Y.Z.tar.gz / .zip   runtime files only (profile, modules, scripts, docs)
#   shellmate-install.sh            the online installer (scripts/get-shellmate.sh)
#   SHA256SUMS                      checksums for all of the above
#   RELEASE_NOTES.md                this version's CHANGELOG section (not an asset)

set -euo pipefail

usage() {
  echo "Usage: scripts/release.sh vX.Y.Z [out_dir]" >&2
}

[[ $# -ge 1 ]] || { usage; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac

version="${1#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "release: bad version '$1'" >&2; usage; exit 2; }

repo_root="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${2:-$repo_root/dist}"

file_version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
if [[ "$file_version" != "$version" ]]; then
  echo "release: VERSION file says '$file_version' but you asked for '$version'" >&2
  exit 1
fi
if ! grep -q "^## ${version} " "$repo_root/docs/v1.0/CHANGELOG.md"; then
  echo "release: docs/v1.0/CHANGELOG.md has no '## ${version} ...' section" >&2
  exit 1
fi
command -v zip >/dev/null 2>&1 || { echo "release: 'zip' is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "release: 'tar' is required" >&2; exit 1; }

name="shellmate-${version}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/$name" "$out"
out="$(cd -P -- "$out" && pwd)"
rm -f "$out/$name.tar.gz" "$out/$name.zip" "$out/shellmate-install.sh" "$out/SHA256SUMS" "$out/RELEASE_NOTES.md"

cp -p "$repo_root/.bash_profile" "$repo_root/VERSION" "$repo_root/readme.md" "$stage/$name/"
cp -p "$repo_root/docs/v1.0/CHANGELOG.md" "$stage/$name/CHANGELOG.md"
cp -Rp "$repo_root/profile.d" "$repo_root/scripts" "$stage/$name/"
# Not for users: a developer's personal overrides, and repo-only dev tools.
rm -f "$stage/$name/profile.d/local.sh" "$stage/$name/scripts/docker-test.sh" "$stage/$name/scripts/release.sh"

# COPYFILE_DISABLE: keep macOS tar from adding ._ metadata files.
(cd "$stage" && COPYFILE_DISABLE=1 tar -czf "$out/$name.tar.gz" "$name")
(cd "$stage" && zip -qr "$out/$name.zip" "$name")
cp -p "$repo_root/scripts/get-shellmate.sh" "$out/shellmate-install.sh"

(
  cd "$out"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$name.tar.gz" "$name.zip" shellmate-install.sh > SHA256SUMS
  else
    shasum -a 256 "$name.tar.gz" "$name.zip" shellmate-install.sh > SHA256SUMS
  fi
)

awk -v v="$version" '
  $0 ~ "^## " v " " { on = 1; next }
  on && /^## / { exit }
  on { print }
' "$repo_root/docs/v1.0/CHANGELOG.md" > "$out/RELEASE_NOTES.md"

echo "release: built $name in $out"
ls -1 "$out"
