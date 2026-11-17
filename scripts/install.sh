#!/usr/bin/env bash
set -euo pipefail

# ShellMate installer.
# - Copies the runtime files into an install dir (default: ~/.my-mac-bash-profile)
#   and links ~/.bash_profile to it (or links straight to the checkout with --link-repo).
# - Backs up anything it replaces (unless --no-backup). Safe to re-run.
# - On Linux, makes ~/.bashrc load ~/.bash_profile for non-login terminals.
# - Offers to install recommended tools with the system package manager. It
#   always asks first, and never installs them without a terminal or with --yes
#   alone (use --bootstrap auto to install without asking).

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [options]

Install ShellMate for the current user. Safe to re-run: anything it replaces is backed up.

Options:
  --repo <path>          Where the ShellMate files are (default: this script's checkout)
  --install-dir <path>   Copy ShellMate here and link to it (default: ~/.my-mac-bash-profile)
  --link-repo            Link straight to the checkout instead of copying it
  --target <path>        Profile to link (default: ~/.bash_profile)
  --dry-run, -n          Show what would change, without changing anything
  --no-backup            Don't back up files that are replaced
  --yes, -y              Don't ask before replacing files (for scripts)
  -h, --help             Show this help

Recommended tools (installed with apt, dnf, yum, pacman, zypper, apk or Homebrew):
  --bootstrap <mode>     ask    Ask before installing them (default). Skipped when
                                there's no terminal to ask, or with --yes.
                         auto   Install them for this OS without asking
                         linux, macos   Same as auto, for that OS
                         none   Don't install or ask about them
  --full                 Include optional extras (7-Zip, unrar, wireless-tools, ...)

Exit codes: 0 success, 1 error, 2 usage error
EOF
}

# ------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------

c_reset="" c_bold="" c_dim="" c_green="" c_cyan=""
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  c_reset=$'\033[0m' c_bold=$'\033[1m' c_dim=$'\033[2m' c_green=$'\033[32m' c_cyan=$'\033[36m'
fi
e_reset="" e_red="" e_yellow=""
if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  e_reset=$'\033[0m' e_red=$'\033[31m' e_yellow=$'\033[33m'
fi

case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*)
    s_ok='✓' s_warn='!' s_err='✗' s_dry='○' s_ask='?' s_arrow='→'
    s_rule='──────────────────────────────────'
    ;;
  *)
    s_ok='+' s_warn='!' s_err='x' s_dry='-' s_ask='?' s_arrow='->'
    s_rule='----------------------------------'
    ;;
esac

ok()      { printf '  %s%s%s %s\n' "$c_green" "$s_ok" "$c_reset" "$*"; }
info()    { printf '    %s%s%s\n' "$c_dim" "$*" "$c_reset"; }
warn()    { printf '  %s%s%s %s\n' "$e_yellow" "$s_warn" "$e_reset" "$*" >&2; }
fail()    { printf '  %s%s%s %s\n' "$e_red" "$s_err" "$e_reset" "$*" >&2; exit 1; }
section() { printf '\n  %s%s%s\n' "$c_bold" "$*" "$c_reset"; }

usage_error() {
  printf 'install.sh: %s\n' "$*" >&2
  printf "Run 'scripts/install.sh --help' for usage.\n" >&2
  exit 2
}

# will: describe a step in --dry-run. did: confirm a finished step otherwise.
will() { if [[ "$dry_run" -eq 1 ]]; then printf '  %s%s%s %s\n' "$c_cyan" "$s_dry" "$c_reset" "$*"; fi; }
did()  { if [[ "$dry_run" -eq 0 ]]; then ok "$*"; fi; }

# Show paths under $HOME as ~/...
pretty() {
  local p="$1" tilde='~'
  if [[ -n "${HOME:-}" && "$p" == "$HOME"/* ]]; then
    printf '%s/%s' "$tilde" "${p#"$HOME"/}"
  else
    printf '%s' "$p"
  fi
}

run() {
  if [[ "$dry_run" -eq 1 ]]; then
    local q=() a
    for a in "$@"; do
      q+=("$(printf '%q' "$a")")
    done
    printf '    %s$ %s%s\n' "$c_dim" "${q[*]}" "$c_reset"
  else
    "$@"
  fi
}

# Usage: ask "question" <y|n>   (the default answer). Returns 0 for yes.
ask() {
  local question="$1" def="$2" hint reply
  if [[ "$def" == "y" ]]; then hint='[Y/n]'; else hint='[y/N]'; fi
  while true; do
    printf '  %s%s%s %s %s%s%s ' "$c_cyan" "$s_ask" "$c_reset" "$question" "$c_dim" "$hint" "$c_reset"
    reply=""
    IFS= read -r reply || printf '\n'
    case "$reply" in
      "")
        if [[ "$def" == "y" ]]; then return 0; fi
        return 1
        ;;
      [yY]|[yY][eE][sS]) return 0 ;;
      [nN]|[nN][oO]) return 1 ;;
      *) info "Please answer y or n." ;;
    esac
  done
}

# Usage: confirm "question" <y|n>
# Yes with --yes or --dry-run; no when there's no terminal to ask.
confirm() {
  if [[ "$assume_yes" -eq 1 || "$dry_run" -eq 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then return 1; fi
  ask "$1" "$2"
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

is_linux() {
  [[ "$(uname -s 2>/dev/null || echo 'Unknown')" != "Darwin" ]]
}

now_stamp() {
  date +%Y%m%d-%H%M%S 2>/dev/null || echo "now"
}

unique_backup_path() {
  # Usage: unique_backup_path <path>
  # Returns a non-existing path by appending .N if needed.
  local base="$1"
  local candidate="$base"
  local n=1
  while [[ -e "$candidate" || -L "$candidate" ]]; do
    candidate="$base.$n"
    n=$((n + 1))
  done
  printf '%s' "$candidate"
}

is_same_symlink() {
  # Usage: is_same_symlink <link> <expected_target>
  local link="$1"
  local expected="$2"
  [[ -L "$link" ]] || return 1
  local actual
  actual="$(readlink "$link" 2>/dev/null || echo '')"
  [[ "$actual" == "$expected" ]]
}

abs_path() {
  # Resolve an absolute path without relying on GNU readlink -f.
  # Works for directories and existing files.
  # For non-existing paths, it resolves the parent directory and appends basename.
  local p="$1"
  # Absolute paths: if we can't resolve (e.g., parent doesn't exist during --dry-run),
  # return the absolute path as-is.
  if [[ "$p" == /* ]]; then
    if [[ -d "$p" ]]; then
      (cd -P -- "$p" 2>/dev/null && pwd) && return 0
    fi
    local d b
    d="$(dirname "$p")"
    b="$(basename "$p")"
    if [[ -d "$d" ]]; then
      (cd -P -- "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$b") && return 0
    fi
    printf '%s\n' "$p"
    return 0
  fi

  # Relative paths.
  if [[ -d "$p" ]]; then
    (cd -P -- "$p" 2>/dev/null && pwd) && return 0
  fi
  local d b
  d="$(dirname "$p")"
  b="$(basename "$p")"
  if [[ -d "$d" ]]; then
    (cd -P -- "$d" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$b") && return 0
  fi
  # Last resort: anchor to current working directory.
  (cd -P -- "$(pwd -P)" 2>/dev/null && printf '%s/%s\n' "$(pwd)" "$p")
}

# ------------------------------------------------------------------------------
# Steps
# ------------------------------------------------------------------------------

deploy_install_dir() {
  # Usage: deploy_install_dir <src_repo_root> <install_dir>
  # Copies the runtime files into install_dir.
  local src_root="$1"
  local dest="$2"
  local old_version="" what="ShellMate" bkp f

  if [[ -e "$dest" && ! -d "$dest" ]]; then
    fail "$(pretty "$dest") exists and is not a directory."
  fi

  if [[ -d "$dest" ]]; then
    if [[ -r "$dest/VERSION" ]]; then
      old_version="$(tr -d '[:space:]' <"$dest/VERSION" 2>/dev/null || true)"
    fi
    [[ -z "$old_version" ]] || what="ShellMate $old_version"

    local action="Update it to ${version:-this version}?"
    [[ -z "$version" || "$old_version" != "$version" ]] || action="Reinstall it?"
    if ! confirm "$what is already installed in $(pretty "$dest"). $action" y; then
      if [[ ! -t 0 ]]; then
        warn "Kept the existing install in $(pretty "$dest"). Re-run with --yes to update it."
      else
        info "Kept the existing install in $(pretty "$dest")."
      fi
      return 0
    fi

    if [[ "$backup" -eq 1 ]]; then
      bkp="$(unique_backup_path "$dest.bak.$(now_stamp)")"
      will "Would back up $what to $(pretty "$bkp")"
      run mv "$dest" "$bkp"
      did "Backed up $what to $(pretty "$bkp")"
    else
      will "Would remove $what from $(pretty "$dest")"
      run rm -rf "$dest"
      did "Removed $what from $(pretty "$dest")"
    fi
  fi

  will "Would copy ShellMate${version:+ $version} to $(pretty "$dest")"
  run mkdir -p "$dest"
  run cp -p "$src_root/.bash_profile" "$dest/.bash_profile"
  run cp -R "$src_root/profile.d" "$dest/profile.d"
  run cp -R "$src_root/scripts" "$dest/scripts"
  if [[ -f "$src_root/VERSION" ]]; then
    run cp -p "$src_root/VERSION" "$dest/VERSION"
  fi

  # Ensure scripts remain executable (portable loop, no find -exec assumptions).
  # Skipped in --dry-run: the copied files don't exist yet.
  if [[ "$dry_run" -eq 0 && -d "$dest/scripts" ]]; then
    for f in "$dest/scripts"/*.sh; do
      [[ -e "$f" ]] || continue
      run chmod +x "$f" || true
    done
  fi
  did "Installed ShellMate${version:+ $version} in $(pretty "$dest")"
}

link_profile() {
  # Usage: link_profile <target> <profile>
  local target="$1" profile="$2" bkp

  if is_same_symlink "$target" "$profile"; then
    ok "$(pretty "$target") already points to ShellMate"
    return 0
  fi

  if [[ -e "$target" || -L "$target" ]]; then
    local question
    question="$(pretty "$target") already exists. Replace it?"
    [[ "$backup" -eq 0 ]] || question="$question (a backup is kept)"
    if ! confirm "$question" n; then
      if [[ ! -t 0 ]]; then
        fail "$(pretty "$target") already exists. Re-run with --yes to replace it (a backup is kept)."
      fi
      fail "Stopped. $(pretty "$target") was left unchanged."
    fi
    if [[ "$backup" -eq 1 ]]; then
      bkp="$(unique_backup_path "$target.bak.$(now_stamp)")"
      will "Would back up your current $(pretty "$target") to $(pretty "$bkp")"
      run mv "$target" "$bkp"
      did "Backed up your current $(pretty "$target") to $(pretty "$bkp")"
    else
      run rm -rf "$target"
    fi
  fi

  will "Would link $(pretty "$target") $s_arrow $(pretty "$profile")"
  run ln -s "$profile" "$target"
  did "Linked $(pretty "$target") $s_arrow $(pretty "$profile")"
}

ensure_bashrc_sources_bash_profile() {
  # Fedora and many Linux terminals start interactive shells as non-login shells.
  # Bash reads ~/.bashrc in that case, not ~/.bash_profile.
  #
  # This makes the install more "it just works" by ensuring ~/.bashrc sources
  # ~/.bash_profile (guarded to avoid recursion if users later source ~/.bashrc
  # from ~/.bash_profile).
  local bashrc="${HOME}/.bashrc"
  local begin_marker="# >>> my-mac-bash-profile (source .bash_profile for non-login shells) >>>"
  local end_marker="# <<< my-mac-bash-profile <<<"

  [[ -n "${HOME:-}" ]] || return 0

  if [[ -f "$bashrc" ]] && grep -qF "$begin_marker" "$bashrc" 2>/dev/null; then
    return 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    will "Would add this to $(pretty "$bashrc") so new terminals load ShellMate:"
    {
      printf '%s\n' "$begin_marker"
      printf '%s\n' "# If this terminal starts Bash as a non-login shell (common on Fedora),"
      printf '%s\n' "# load the login profile too."
      printf '%s\n' "if [[ \$- == *i* ]] && [[ -z \"\${__MMBP_BASHRC_SOURCED_PROFILE:-}\" ]] && [[ -f \"\$HOME/.bash_profile\" ]]; then"
      printf '%s\n' "  __MMBP_BASHRC_SOURCED_PROFILE=1"
      printf '%s\n' "  # shellcheck source=/dev/null"
      printf '%s\n' "  source \"\$HOME/.bash_profile\""
      printf '%s\n' "fi"
      printf '%s\n' "$end_marker"
    } | while IFS= read -r line; do info "  $line"; done
    return 0
  fi

  touch "$bashrc"
  {
    printf '\n%s\n' "$begin_marker"
    cat <<'EOF'
# If this terminal starts Bash as a non-login shell (common on Fedora),
# load the login profile too.
if [[ $- == *i* ]] && [[ -z "${__MMBP_BASHRC_SOURCED_PROFILE:-}" ]] && [[ -f "$HOME/.bash_profile" ]]; then
  __MMBP_BASHRC_SOURCED_PROFILE=1
  # shellcheck source=/dev/null
  source "$HOME/.bash_profile"
fi
EOF
    printf '%s\n' "$end_marker"
  } >>"$bashrc"
  ok "Updated $(pretty "$bashrc") so new terminals load ShellMate"
}

run_bootstrap() {
  # Usage: run_bootstrap <script> [args...]
  local script="$1"
  shift
  if [[ "$dry_run" -eq 1 ]]; then
    bash "$script" "$@" --dry-run
  else
    bash "$script" "$@"
  fi
}

offer_tools() {
  # Usage: offer_tools <os> <bootstrap-script> <path-to-show-for-later>
  # Lists the recommended tools that are missing and asks before installing them.
  local os="$1" script="$2" later="$3"
  local listing line manager="" core="" optional="" how args=()

  listing="$(bash "$script" --list 2>/dev/null)" || listing=""
  while IFS= read -r line; do
    case "$line" in
      manager=*)  manager="${line#manager=}" ;;
      core=*)     core="${line#core=}" ;;
      optional=*) optional="${line#optional=}" ;;
    esac
  done <<EOF
$listing
EOF

  section "Recommended tools"

  if [[ -z "$manager" ]]; then
    if [[ "$os" == "macos" ]]; then
      info "Homebrew isn't installed, so this step was skipped. ShellMate works without it."
      info "To add the tools later, install Homebrew (https://brew.sh) and run:"
    else
      info "No supported package manager found (apt, dnf, yum, pacman, zypper, apk)."
      info "ShellMate works without these tools. To add them later, run:"
    fi
    info "  bash $(pretty "$later")"
    return 0
  fi

  if [[ -z "$core" && ( "$full" -eq 0 || -z "$optional" ) ]]; then
    ok "Recommended tools are already installed"
    if [[ -n "$optional" ]]; then
      info "Optional extras ($optional) can be added with:"
      info "  bash $(pretty "$later") --full"
    fi
    return 0
  fi

  info "System packages that let sysinfo, netinfo and extract do more."
  info "ShellMate works fine without them."
  printf '\n'
  if [[ -n "$core" ]]; then
    printf '    %-10s %s%s%s\n' "Missing:" "$c_bold" "$core" "$c_reset"
  fi
  if [[ -n "$optional" ]]; then
    printf '    %-10s %s\n' "Extras:" "$optional"
  fi
  printf '\n'

  [[ "$full" -eq 0 ]] || args+=(--full)

  if [[ "$dry_run" -eq 1 ]]; then
    will "Would ask before installing them. The commands would be:"
    run_bootstrap "$script" ${args[@]+"${args[@]}"} || true
    return 0
  fi
  if [[ "$assume_yes" -eq 1 ]]; then
    info "Skipped: --yes doesn't install system packages (use --bootstrap auto for that)."
    info "To install them later, run:  bash $(pretty "$later")"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    info "Skipped (no terminal to ask). To install them later, run:"
    info "  bash $(pretty "$later")"
    return 0
  fi

  how="$manager"
  [[ "$manager" == "brew" ]] && how="Homebrew"
  if [[ "$os" == "linux" && "$(id -u 2>/dev/null || echo 1)" != "0" ]]; then
    how="$how (uses sudo)"
  fi

  if [[ -n "$core" ]]; then
    if ! ask "Install the missing tools now with $how?" y; then
      info "Skipped. To install them later, run:  bash $(pretty "$later")"
      return 0
    fi
    if [[ "$full" -eq 0 && -n "$optional" ]] && ask "Also install the optional extras?" n; then
      args+=(--full)
    fi
  else
    # Only extras are missing, and --full asked for them.
    if ! ask "Install the optional extras now with $how?" y; then
      info "Skipped. To install them later, run:  bash $(pretty "$later") --full"
      return 0
    fi
  fi

  printf '\n'
  if run_bootstrap "$script" ${args[@]+"${args[@]}"}; then
    ok "Recommended tools installed"
  else
    warn "Some tools couldn't be installed. ShellMate works without them."
    info "To try again later, run:  bash $(pretty "$later")"
  fi
}

# ------------------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------------------

dry_run=0
backup=1
bootstrap="ask"
full=0
assume_yes=0

repo_root=""
install_dir=""
link_repo=0
target="${HOME}/.bash_profile"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || usage_error "--repo requires a value"
      repo_root="$2"
      shift
      ;;
    --target)
      [[ $# -ge 2 ]] || usage_error "--target requires a value"
      target="$2"
      shift
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || usage_error "--install-dir requires a value"
      install_dir="$2"
      shift
      ;;
    --link-repo)
      link_repo=1
      ;;
    --dry-run|-n)
      dry_run=1
      ;;
    --no-backup)
      backup=0
      ;;
    --yes|-y)
      assume_yes=1
      ;;
    --bootstrap)
      [[ $# -ge 2 ]] || usage_error "--bootstrap requires a value"
      bootstrap="$2"
      shift
      ;;
    --full)
      full=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage_error "unknown option: $1"
      ;;
  esac
  shift
done

case "$bootstrap" in
  ask|auto|linux|macos|none) ;;
  *) usage_error "unknown --bootstrap value: $bootstrap (expected ask, auto, linux, macos or none)" ;;
esac

if [[ "$link_repo" -eq 1 && -n "$install_dir" ]]; then
  usage_error "--link-repo cannot be combined with --install-dir"
fi

if [[ -z "$repo_root" ]]; then
  # script_dir/.. is repo root
  script_dir="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_root="$(cd -P -- "$script_dir/.." && pwd)"
fi

repo_root="$(abs_path "$repo_root")"
repo_profile="$repo_root/.bash_profile"

if [[ ! -r "$repo_profile" ]]; then
  fail "Could not find ShellMate's .bash_profile in $(pretty "$repo_root")."
fi

version=""
if [[ -r "$repo_root/VERSION" ]]; then
  version="$(tr -d '[:space:]' <"$repo_root/VERSION" 2>/dev/null || true)"
fi

# Default deployment mode: copy runtime files into install_dir and link to that.
# Use --link-repo to link directly to the checkout instead.
if [[ "$link_repo" -eq 0 && -z "$install_dir" ]]; then
  install_dir="$HOME/.my-mac-bash-profile"
fi

# ------------------------------------------------------------------------------
# Install
# ------------------------------------------------------------------------------

printf '\n  %sShellMate%s installer%s\n' "$c_bold" "${version:+ $version}" "$c_reset"
printf '  %s%s%s\n' "$c_dim" "$s_rule" "$c_reset"
if [[ "$dry_run" -eq 1 ]]; then
  info "Dry run: showing what would change. Nothing will be modified."
fi

target_dir="$(dirname "$target")"
if [[ ! -d "$target_dir" ]]; then
  run mkdir -p "$target_dir"
fi
target_abs="$(abs_path "$target")"

if [[ -n "$install_dir" ]]; then
  install_dir_abs="$(abs_path "$install_dir")"
  printf '\n    %-12s %s\n' "Install to" "$(pretty "$install_dir_abs")"
else
  printf '\n    %-12s %s %s(linked to this checkout)%s\n' "Install to" "$(pretty "$repo_root")" "$c_dim" "$c_reset"
fi
printf '    %-12s %s\n\n' "Profile" "$(pretty "$target_abs")"

if [[ -n "$install_dir" ]]; then
  deploy_install_dir "$repo_root" "$install_dir_abs"
  profile_abs="$(abs_path "$install_dir_abs/.bash_profile")"
  runtime_root="$install_dir_abs"
else
  profile_abs="$(abs_path "$repo_profile")"
  runtime_root="$repo_root"
fi

link_profile "$target_abs" "$profile_abs"

# On Linux, ensure non-login shells still load ~/.bash_profile via ~/.bashrc.
if is_linux; then
  ensure_bashrc_sources_bash_profile
fi

# ------------------------------------------------------------------------------
# Recommended tools
# ------------------------------------------------------------------------------

os="linux"
[[ "$(uname -s 2>/dev/null || echo 'Unknown')" == "Darwin" ]] && os="macos"

case "$bootstrap" in
  none)
    ;;
  ask)
    bs="$repo_root/scripts/bootstrap-$os.sh"
    [[ -r "$bs" ]] || fail "$(pretty "$bs") not found or not readable."
    offer_tools "$os" "$bs" "$runtime_root/scripts/bootstrap-$os.sh"
    ;;
  *)
    [[ "$bootstrap" == "auto" ]] && bootstrap="$os"
    bs="$repo_root/scripts/bootstrap-$bootstrap.sh"
    [[ -r "$bs" ]] || fail "$(pretty "$bs") not found or not readable."
    section "Recommended tools"
    args=()
    [[ "$full" -eq 1 && "$bootstrap" == "linux" ]] && args+=(--full)
    [[ "$full" -eq 1 && "$bootstrap" == "macos" ]] && args+=(--full)
    run_bootstrap "$bs" ${args[@]+"${args[@]}"} || fail "Installing the recommended tools failed."
    ;;
esac

# ------------------------------------------------------------------------------
# Done
# ------------------------------------------------------------------------------

printf '\n'
if [[ "$dry_run" -eq 1 ]]; then
  printf '  %sDry run finished. Nothing was changed.%s\n\n' "$c_bold" "$c_reset"
else
  printf '  %s%s ShellMate%s is ready.%s\n' "$c_green$c_bold" "$s_ok" "${version:+ $version}" "$c_reset"
  info "Open a new terminal, or run:  source $(pretty "$target_abs")"
  printf '\n'
fi
