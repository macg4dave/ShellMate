#!/usr/bin/env bash
# Runs inside a ShellMate test container (see docker/Dockerfile).
# Works on a throwaway copy of /src so the image itself stays pristine.

set -euo pipefail

target="${SHELLMATE_TEST_TARGET:-unknown}"
work="$HOME/shellmate"

echo "==> [$target] $(bash --version | head -n1)"

rm -rf "$work"
cp -R /src "$work"
cd "$work"

# Defensive: a Windows checkout without .gitattributes applied may carry CRLF.
# Strip it so we test the code, not the checkout. (Committed files are LF.)
find . -path ./.git -prune -o -type f \( -name '*.sh' -o -name '.bash_profile' -o -name 'Makefile' \) -print \
  | while IFS= read -r f; do
      if grep -q $'\r' "$f"; then
        sed -i 's/\r$//' "$f"
      fi
    done

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> [$target] make lint"
  make lint
else
  echo "==> [$target] make lint: skipped (shellcheck not installed in this image)"
fi

echo "==> [$target] make test"
make test

# Real install into this container's (disposable) HOME, then confirm a fresh
# login shell picks up the helpers.
echo "==> [$target] install.sh + login shell"
bash scripts/install.sh --repo "$work" --yes --bootstrap none
bash -lc 'for fn in sysinfo netinfo extract pathinfo; do type "$fn" >/dev/null || { echo "missing: $fn" >&2; exit 1; }; done'
NETINFO_EXTERNAL_IP=0 bash -lc 'sysinfo --kv >/dev/null && netinfo --kv >/dev/null'

echo "==> [$target] all checks passed"
