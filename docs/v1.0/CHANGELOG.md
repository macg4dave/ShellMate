# Changelog

All notable changes to this project will be documented in this file.

This repo is a portable Bash login profile (macOS + Linux) with helper functions.

## Unreleased

- New `motd` module: the first 3 interactive shells show a welcome with basic usage; `motd --edit` sets your own login message, `motd --off`/`--on` toggles it
- Fix: `extract foo.zip` now actually extracts (it used to only list the archive)
- Fix: `extract <archive> <dest>` honours `dest`; output is quiet unless `-v`; zip/7z/rar and single-file formats no longer overwrite existing files without `--force`; `.Z` files work (falls back to `gzip`); `--list` and unsupported formats no longer create a directory
- Fix: `extract` path-traversal check now works for 7z archives
- Fix: on first login, `ls`/`PS1`/PATH setup ran before OS detection (wrong `ls` alias on macOS, non-existent `/opt/local` dirs added to PATH)
- Fix: `pathinfo` shows a trailing `:` in PATH (an implicit current-directory entry)
- Fix: `netinfo` makes one ipinfo request per run instead of up to three when offline
- `extract`, `jd` and `jdir` follow the helper contract for unknown flags (`<helper>: unknown option`, exit 2)
- `sysinfo` no longer leaks internal functions/variables (`main`, `find_os`, `human_bytes`, `os_name`, `ram_total`, ...) into your shell; all are now `_sysinfo_*`
- `sysinfo` CPU percentages are current usage (short sample) instead of the average since boot
- `sysinfo` on macOS: correct uptime and load average (via `sysctl`), network counters for the default-route interface instead of hard-coded `en0`, human-readable sizes without `numfmt`, disk "used" computed from exact byte counts, boot volume name from `diskutil` (no Finder automation prompt)
- `netinfo --kv`: `local_ip` on Linux is now a bare address (was `192.168.1.5/24`), matching macOS, and comes from the default interface
- `netinfo`: external IP must look like an IP (captive-portal HTML is no longer shown or cached); control characters are stripped from network-provided text; macOS VPN list ignores the IPv6-only `utun` interfaces macOS creates itself; Linux default route parsed by keyword
- `flushdns --dry-run` now prints the best-effort commands it used to hide
- Removed the unused deprecation helper (`__bp_deprecated_env`) and `docs/v2.0/deprecation_policy.md`
- Auto testing: `make hooks` enables a pre-commit hook running `make lint` + `make test`; CI also runs weekly and on demand
- CI pins ShellCheck (v0.10.0) so lint results don't change with runner images
- Lint/test tooling: shared `.shellcheckrc`, `make lint` works across ShellCheck 0.9–0.11, `make docker-test` works with Podman, new `tests/regressions.sh`
- Project renamed to **ShellMate** (runtime paths such as `~/.my-mac-bash-profile` are unchanged)
- `AGENTS.md` / `CLAUDE.md` agent rules shared by Codex, Claude Code and Copilot
- Docker test targets (ubuntu, debian, fedora, bash 3.2) via `make docker-test`, also run in CI
- P1: macOS Bash 3.2 compatibility fixes and CI for lint + smoke tests
- P2: `--help` and machine-readable `--kv` modes for helpers
- P3: module toggles and local override support
- P4: installer script (`scripts/install.sh`) with `--dry-run` and backups
- P5: `extract` aborts on obvious path traversal by default (`--force` to override)
