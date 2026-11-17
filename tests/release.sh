#!/usr/bin/env bash
# Build the release files and install from them with the online installer,
# end to end, using file:// URLs (no network). Skips when zip/curl are missing.

set -euo pipefail

repo_root="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "release test: $*" >&2
  exit 1
}

# Always: the VERSION file must have a matching CHANGELOG section.
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION file is not X.Y.Z: '$version'"
grep -q "^## ${version} " "$repo_root/docs/v1.0/CHANGELOG.md" || fail "CHANGELOG has no '## ${version} ...' section"

for tool in zip unzip curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "release test: skipped ($tool not installed)"
    exit 0
  fi
done

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

dist="$tmp/dist"
bash "$repo_root/scripts/release.sh" "v$version" "$dist" >/dev/null

name="shellmate-$version"
for f in "$name.tar.gz" "$name.zip" shellmate-install.sh SHA256SUMS RELEASE_NOTES.md; do
  [[ -s "$dist/$f" ]] || fail "missing release file: $f"
done
(cd "$dist" && if command -v sha256sum >/dev/null 2>&1; then sha256sum -c SHA256SUMS; else shasum -a 256 -c SHA256SUMS; fi) >/dev/null \
  || fail "SHA256SUMS does not match the files"

# Archives hold the runtime, not dev-only files.
listing="$(tar -tzf "$dist/$name.tar.gz")"
for f in .bash_profile VERSION profile.d/motd.sh scripts/install.sh; do
  [[ "$listing" == *"$name/$f"* ]] || fail "tarball is missing $f"
done
for f in profile.d/local.sh scripts/docker-test.sh tests/; do
  [[ "$listing" != *"$name/$f"* ]] || fail "tarball should not contain $f"
done
unzip -l "$dist/$name.zip" | grep -q "$name/profile.d/motd.sh" || fail "zip is missing profile.d/motd.sh"

# Online installer, end to end, into a throwaway HOME.
home="$tmp/home"
mkdir -p "$home"
HOME="$home" SHELLMATE_VERSION="v$version" SHELLMATE_DOWNLOAD_BASE="file://$dist" \
  bash "$dist/shellmate-install.sh" --yes </dev/null >/dev/null \
  || fail "online installer failed"
[[ -L "$home/.bash_profile" ]] || fail "online installer did not link ~/.bash_profile"
[[ "$(cat "$home/.my-mac-bash-profile/VERSION")" == "$version" ]] || fail "installed VERSION is wrong"
doctor="$(HOME="$home" bash --noprofile --norc -c 'source "$HOME/.bash_profile"; mm_bash_profile_doctor')"
[[ "$doctor" == *"shellmate_version=$version"* ]] || fail "doctor does not report shellmate_version=$version"

# A tampered download must be refused.
printf 'tampered' >> "$dist/$name.tar.gz"
if HOME="$home" SHELLMATE_VERSION="v$version" SHELLMATE_DOWNLOAD_BASE="file://$dist" \
  bash "$dist/shellmate-install.sh" --yes </dev/null >/dev/null 2>&1; then
  fail "online installer accepted a tarball with the wrong checksum"
fi

echo "release test: ok ($name)"
