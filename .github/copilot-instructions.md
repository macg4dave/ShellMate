# Copilot instructions

The canonical AI-agent rules for ShellMate are in [`AGENTS.md`](../AGENTS.md) at the
repo root — follow them. Key points, in case that file isn't loaded:

- Bash login profile for macOS + Linux. **Bash 3.2 compatible** (no `declare -A`, `mapfile`, `${var,,}`, etc.).
- Sourcing `.bash_profile` / `profile.d/*.sh` must never hit the network, prompt, hang, or print to stdout.
- Guard non-portable commands with `command -v` and/or `uname -s` checks; fail soft.
- Helpers follow `docs/v2.0/helper_contract.md` (`--help` → 0, unknown flag → 2, missing tool → `N/A`, stable `--kv` key order).
- Keep `shellcheck --shell=bash` clean; run `make lint` and `make test`.
- No secrets, no heavy new dependencies, no breaking changes without asking first and a CHANGELOG note.
