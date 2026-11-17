# AGENTS.md — rules for AI coding agents (Codex, Claude Code, Copilot, …)

This is the **single source of truth** for AI agent instructions in this repo.
`CLAUDE.md` imports it and `.github/copilot-instructions.md` points to it, so edit
rules here, not there.

## What ShellMate is

ShellMate is a version-controlled **Bash** login profile for **macOS and Linux**:
a small set of safe, opt-in helpers (`sysinfo`, `netinfo`, `extract`, `flushdns`,
`jd`/`jdir`, `pathinfo`, macOS-only `cdf`/`gosu`) loaded from `~/.bash_profile`.
Priorities, in order: **never break the user's shell → portable → fast startup → features.**

## Layout

| Path | Purpose |
| --- | --- |
| `.bash_profile` | Entry point. Resolves its own dir (even via symlink), loads `profile.d/*.sh`, honors toggles + local overrides. |
| `profile.d/*.sh` | One module per feature. `10-common.sh` = shared helpers (`has_cmd`, `path_prepend`); `osx.sh` / `linux.sh` are OS-gated. |
| `scripts/install.sh` | Conservative installer (copy or `--link-repo`, backups, `--dry-run`, `--yes`). |
| `scripts/bootstrap-*.sh` | Optional dependency installers; must support `--dry-run`. |
| `tests/*.sh` | Plain-bash tests run by `make test`. All use a throwaway `$HOME`. |
| `docker/`, `scripts/docker-test.sh` | Disposable Linux test containers (ubuntu, debian, fedora, bash 3.2). |
| `docs/v2.0/` | Contracts and roadmap — read before changing behavior. |

## Contracts you must not break

Read the relevant doc before touching that area:

- **`docs/v2.0/compatibility_contract.md`** — Bash **3.2** (macOS `/bin/bash`) and 4.x+ are both supported; install paths are part of the contract.
- **`docs/v2.0/helper_contract.md`** — `-h/--help` exits 0; unknown flag exits 2 with `<helper>: unknown option`; runtime error exits 1; missing optional tool ⇒ `N/A`, never a failure; `--kv` keys and **key order** are stable API.

### Safe-to-source (non-negotiable)

Sourcing `.bash_profile` or any `profile.d/*.sh` must **not**: make network calls,
prompt, hang, run slow/heavy pipelines, write outside normal shell state, or print
to stdout. Warnings go to stderr and only in interactive shells (`__bp_warn`).
Startup has a time budget enforced by `tests/perf-startup.sh` — do expensive work
lazily inside the helper function, not at source time.

## Bash rules

- **Bash 3.2 compatible.** No associative arrays (`declare -A`), `mapfile`/`readarray`, `${var,,}`/`${var^^}`, `|&`, `&>>`, `coproc`, negative array indices, or `declare -n`. Guard `"${arr[@]}"` on possibly-empty arrays under `set -u`.
- Guard every non-portable command: `command -v foo >/dev/null 2>&1` (or `has_cmd foo`) and/or `[[ "$(uname -s)" == Darwin ]]`. Fail soft with a clear message.
- macOS ships BSD tools (`sed -i ''`, `stat -f`, `date` without `%N`, no `numfmt`/`timeout` by default). Don't assume GNU flags.
- Module files are **sourced**: no `set -e`/`set -u`/`exit` at top level; use `local` in functions; prefix private helpers `_<module>_…` to avoid polluting the user's namespace.
- Quote expansions, avoid `eval`, keep `shellcheck --shell=bash` clean. Disable a check only inline, with a reason.
- Function style matches the file you're in; keep banner-comment grouping.
- No new heavy dependencies. No secrets, tokens, or personal hostnames/IPs in any file.

## Workflow

```bash
make lint          # shellcheck (needs shellcheck installed)
make test          # full suite: smoke, perf, safe-source, missing-deps, helper contract, hygiene
make docker-test   # same suite + a real install, in ubuntu/debian/fedora/bash3.2 containers
make docker-test TARGETS="bash32"   # quickest way to catch Bash 4+ syntax
```

- Run `make lint` and `make test` before calling work done (`make hooks` makes git run them on every commit); run `make docker-test TARGETS=bash32` for anything touching shell syntax if Docker is available. Report failures honestly — don't weaken a test to make it pass.
- New helper or new `--kv` key ⇒ update `docs/v2.0/helper_contract.md` **and** `tests/helper_contract.sh`. Ask before adding flags that aren't in the helper contract.
- User-visible change ⇒ update `readme.md` (keep it beginner-friendly) and add a line under `## Unreleased` in `docs/v1.0/CHANGELOG.md`.
- Roadmap status markers: ✅ done, ⏳ in progress, 🟡 not started.
- Small, focused commits. Don't commit or push unless asked.

## Naming note (rename in progress)

The project was renamed from *My-Mac-Bash-profile* to **ShellMate**. Runtime names
still use the old identifiers on purpose — `~/.my-mac-bash-profile`,
`~/.config/my-mac-bash-profile/`, `mm_bash_profile_doctor`, `__MMBP_*` — because
they're part of the compatibility contract. Don't rename them ad hoc; ask first.

## When unsure

Follow existing patterns in neighboring code. If the intended behavior or a
contract question is ambiguous, ask instead of guessing.
