---
title: Release process
repo: ShellMate
doc_version: v2.0
---

<!-- markdownlint-disable MD025 -->

# Release process

This repo is intentionally lightweight: there is no compiled build, just packaged shell files.

## Release artifacts (v3+)

Each release is a **git tag** (`vX.Y.Z`) plus a **GitHub Release** with:

- `shellmate-X.Y.Z.tar.gz` and `shellmate-X.Y.Z.zip` — runtime files only
  (`.bash_profile`, `profile.d/`, `scripts/` minus dev tools, `VERSION`, readme, CHANGELOG)
- `shellmate-install.sh` — the online installer (`scripts/get-shellmate.sh`):
  `curl -fsSL https://github.com/macg4dave/ShellMate/releases/latest/download/shellmate-install.sh | bash`
- `SHA256SUMS` — checksums of the three files above (the installer verifies the tarball)

`scripts/release.sh vX.Y.Z` (or `make dist`) builds these into `dist/`;
`.github/workflows/release.yml` builds and publishes them when a `v*` tag is pushed.
No Homebrew formula/cask is published.

## Preconditions

From a clean checkout of the default branch:

- `make lint` passes
- `make test` passes
- `docs/v1.0/CHANGELOG.md` has an up-to-date `Unreleased` section describing what’s in the release

## Checklist (P0.5 / P4.2)

### 1) Prepare release notes

- Update `docs/v1.0/CHANGELOG.md`:
  - Move items from `Unreleased` into a new dated section (example: `## 3.0.0 — 2026-11-17`)
  - Leave a fresh `## Unreleased` section at the top
- If there are any behavioral changes, ensure `docs/v2.0/migration_from_v1.md` covers them.

### 2) Verify safety + compatibility

Run the full checks:

- `make lint`
- `make test`

Manual spot-checks (quick):

- `bash -lc 'source ./.bash_profile'` (should be silent and fast)
- `sysinfo --kv` and `netinfo --kv` (keys present; `N/A` when optional tools missing)
- `scripts/install.sh --dry-run` (no writes)

### 3) Set the version

- Put the new version in `VERSION` (e.g. `3.0.1`); it must match the CHANGELOG
  section heading (`## 3.0.1 — YYYY-MM-DD`). `tests/release.sh` checks this.
- Optional: `make dist` and try `dist/shellmate-install.sh` locally.

### 4) Tag and push — CI publishes the release

```bash
git tag -a v3.0.1 -m "ShellMate v3.0.1"
git push origin master v3.0.1
```

The Release workflow runs the tests, builds the files and creates the GitHub
Release with the CHANGELOG section as its notes. Check it under Actions.

## Rollback guidance

Because install is a symlink or a copied install dir, rollback is straightforward:

- If you installed by linking to a checkout: `git checkout <previous tag>`
- If you installed via `--install-dir`: re-run `scripts/install.sh` with an older checkout/tag and the same install dir/target

## Versioning policy

- Tags use `vMAJOR.MINOR.PATCH`.
- v2 aims to keep **backward compatibility** by default; breaking changes require explicit migration notes.
