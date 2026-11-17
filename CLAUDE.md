# CLAUDE.md

All project rules live in AGENTS.md (shared with Codex and other agents):

@AGENTS.md

## Claude Code specifics

- Developers may be on Windows: use the Bash tool (Git Bash) for `make`/test commands, not PowerShell. `.gitattributes` forces LF; never write CRLF into shell files.
- `shellcheck` and Docker may not be installed locally. If you can't run `make lint` or `make docker-test`, say so explicitly rather than implying they passed — CI runs both.
