#!/usr/bin/env bash
# Build and run ShellMate's test suite in disposable Linux containers.
#
#   scripts/docker-test.sh              # all targets
#   scripts/docker-test.sh fedora bash32
#   DOCKER=podman scripts/docker-test.sh debian

set -euo pipefail

all_targets=(ubuntu debian fedora bash32)

usage() {
  cat <<EOF
Usage: scripts/docker-test.sh [target ...]

Targets: ${all_targets[*]} (default: all)

Environment:
  DOCKER   container CLI to use (default: docker; podman also works)
EOF
}

repo_root="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
docker_cli="${DOCKER:-docker}"

if ! command -v "$docker_cli" >/dev/null 2>&1; then
  echo "docker-test: '$docker_cli' not found (set DOCKER=podman to use podman)" >&2
  exit 1
fi

targets=()
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    all) targets=("${all_targets[@]}") ;;
    ubuntu|debian|fedora|bash32) targets+=("$arg") ;;
    *) echo "docker-test: unknown target '$arg'" >&2; usage; exit 2 ;;
  esac
done
((${#targets[@]})) || targets=("${all_targets[@]}")

failed=()
for t in "${targets[@]}"; do
  image="shellmate-test:$t"
  echo "=== building $image"
  if ! "$docker_cli" build -f "$repo_root/docker/Dockerfile" --build-arg "TARGET=$t" -t "$image" "$repo_root"; then
    failed+=("$t(build)")
    continue
  fi
  echo "=== running $image"
  if ! "$docker_cli" run --rm "$image"; then
    failed+=("$t")
  fi
done

echo
if ((${#failed[@]})); then
  echo "docker-test: FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "docker-test: ok (${targets[*]})"
