.PHONY: lint test docker-test hooks dist

SHELLCHECK ?= shellcheck

# Shared settings live in .shellcheckrc (also read by editors). Keep flags
# conservative to avoid noisy style churn.
SHELLCHECK_FLAGS ?=

# Every shell file in the repo (incl. the git hook, which has no .sh suffix). profile.d/local.sh is a user's gitignored
# override, so it is not ours to lint.
LINT_FILES := .bash_profile .githooks/pre-commit \
	$(filter-out profile.d/local.sh,$(wildcard profile.d/*.sh)) \
	$(wildcard tests/*.sh scripts/*.sh docker/*.sh)

lint:
	@command -v $(SHELLCHECK) >/dev/null 2>&1 || { \
		echo "make lint: '$(SHELLCHECK)' not found; install ShellCheck (see scripts/bootstrap-*.sh)" >&2; \
		exit 1; }
	@$(SHELLCHECK) --version | sed -n 's/^version: /shellcheck /p'
	@$(SHELLCHECK) $(SHELLCHECK_FLAGS) $(LINT_FILES)
	@echo "lint: ok ($(words $(LINT_FILES)) files)"

test:
	@bash tests/smoke.sh
	@bash tests/perf-startup.sh
	@bash tests/safe-source.sh
	@bash tests/missing-deps.sh
	@bash tests/helper_contract.sh
	@bash tests/regressions.sh
	@bash tests/release.sh
	@bash tests/release-hygiene.sh

# Run the suite in disposable Linux containers (ubuntu, debian, fedora, bash 3.2).
# Narrow with: make docker-test TARGETS="fedora bash32"
TARGETS ?=

docker-test:
	@bash scripts/docker-test.sh $(TARGETS)

# Run lint + tests automatically before each commit (see .githooks/pre-commit).
hooks:
	@git config core.hooksPath .githooks
	@echo "hooks: enabled .githooks (pre-commit runs make lint + make test)"

# Build release files into dist/ (tarball, zip, online installer, SHA256SUMS)
# for the version in the VERSION file. Publishing happens in CI when a v* tag
# is pushed (.github/workflows/release.yml).
dist:
	@bash scripts/release.sh "v$$(cat VERSION)"
