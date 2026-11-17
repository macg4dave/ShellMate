# Changelog

All notable changes to this project will be documented in this file.

This repo is a portable Bash login profile (macOS + Linux) with helper functions.

## Unreleased

- Project renamed to **ShellMate** (runtime paths such as `~/.my-mac-bash-profile` are unchanged)
- `AGENTS.md` / `CLAUDE.md` agent rules shared by Codex, Claude Code and Copilot
- Docker test targets (ubuntu, debian, fedora, bash 3.2) via `make docker-test`, also run in CI
- P1: macOS Bash 3.2 compatibility fixes and CI for lint + smoke tests
- P2: `--help` and machine-readable `--kv` modes for helpers
- P3: module toggles and local override support
- P4: installer script (`scripts/install.sh`) with `--dry-run` and backups
- P5: `extract` aborts on obvious path traversal by default (`--force` to override)
