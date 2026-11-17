<p align="center">
  <!-- When the final ShellMate wordmark is committed, it can replace this mascot header. -->
  <img src="docs/mascot/ruby.png" alt="Ruby, the ShellMate mascot" width="170">
</p>

<h1 align="center">ShellMate</h1>

<p align="center">
  <strong>It's your shell, mate.</strong><br>
  Handy Bash tools, a friendlier terminal, and the same setup across macOS, Linux and Windows Subsystem for Linux.
</p>

<p align="center">
  <a href="https://github.com/macg4dave/ShellMate/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/macg4dave/ShellMate?label=release&color=ad4fe8"></a>
  <img alt="Bash 3.2 and newer" src="https://img.shields.io/badge/Bash-3.2%2B-563d7c">
  <img alt="macOS, Linux and WSL" src="https://img.shields.io/badge/platforms-macOS%20%7C%20Linux%20%7C%20WSL-252b36">
  <a href="https://github.com/macg4dave/ShellMate/issues"><img alt="GitHub issues" src="https://img.shields.io/github/issues/macg4dave/ShellMate?color=538ec6"></a>
</p>

<p align="center">
  <a href="#install-in-one-command">Install</a> ·
  <a href="#meet-your-new-toolbox">Commands</a> ·
  <a href="#where-it-works">Platforms</a> ·
  <a href="#see-it-in-action">Screenshots</a> ·
  <a href="#for-the-tinkerers">Advanced</a>
</p>

---

**ShellMate makes Bash more useful without trying to replace Bash.** It adds small, memorable commands for checking your system, understanding your network, extracting archives, downloading files and keeping your environment tidy.

It's for the person who just wants `extract photo.zip` to work **and** the person who wants stable, scriptable `key=value` output on a headless server.

- **Practical from day one.** No framework to learn, no account to create.
- **One familiar setup.** Take your Bash profile between a Mac, Linux workstation, server and WSL.
- **Respectful of your shell.** Lightweight modular helpers; no daemon, telemetry or background updater.
- **Optional extras stay optional.** Missing tools degrade gracefully where possible. Package installation is offered, not silently forced.
- **Built to be recoverable.** Backups, installer dry-run, module switches and a safe mode.

## Install in one command

On **macOS or Linux**, open a terminal and run:

```bash
curl -fsSL https://github.com/macg4dave/ShellMate/releases/latest/download/shellmate-install.sh | bash
```

That's the published release installer, not an arbitrary checkout of the main branch. It downloads the release archive, checks its SHA-256 checksum when a checksum utility is available, and runs ShellMate's normal installer.

**What changes?** ShellMate is copied to `~/.my-mac-bash-profile`, your `~/.bash_profile` is linked to it, and anything it replaces is backed up by default. On Linux, it also adds a guarded snippet to `~/.bashrc` so non-login terminal windows load it. It offers missing recommended tools and asks before installing system packages.

Open a new Bash terminal, or run:

```bash
source ~/.bash_profile
sysinfo
```

**Want to inspect it before running it?** This works too:

```bash
git clone https://github.com/macg4dave/ShellMate.git
cd ShellMate
bash scripts/install.sh --repo "$(pwd)" --dry-run  # preview changes
bash scripts/install.sh --repo "$(pwd)"            # install
```

You can also download a release ZIP/tarball from [Releases](https://github.com/macg4dave/ShellMate/releases) and run the bundled `scripts/install.sh`. See `bash scripts/install.sh --help` for all options.

> **Already use your own Bash profile?** The installer asks before replacing it and keeps a timestamped backup. Use `--bootstrap none` if you don't want to be offered extra packages; use `--yes` to skip replacement confirmations (it does *not* auto-install system packages).

### A note for Mac users

Modern macOS opens **zsh** by default. ShellMate is for **Bash**, including Apple's system Bash 3.2. You can try it without changing your default shell:

```bash
bash -l
sysinfo
```

### A note for Windows users

Run ShellMate **inside your WSL Linux distribution**, not in PowerShell or Command Prompt. Open Ubuntu, Debian or another Bash-based WSL distro and use the same installation instructions as Linux. Windows Terminal is a great place to run it.

## Meet your new toolbox

No complicated subcommands to memorise. These are the helpers you'll actually reach for:

| Command | What it does | Example |
| --- | --- | --- |
| `sysinfo` | CPU, RAM, disk, uptime, load and network totals in one readable view | `sysinfo --box` |
| `netinfo` | Local hostname, interface, gateway, IP, VPN and optional public-IP details | `netinfo --box` |
| `extract` | Unpack ZIP, TAR, 7z, RAR and other supported archives using installed tools | `extract downloads.zip` |
| `pathinfo` | See every PATH entry and find missing or duplicate directories | `pathinfo --duplicates` |
| `flushdns` | Clear the DNS cache with OS-aware, best-effort handling | `flushdns --dry-run` |
| `jd` | Download a file using wget with resume-friendly behaviour | `jd https://example.org/file.iso` |
| `jdir` | Fetch a directory recursively with wget | `jdir https://example.org/files/` |
| `motd` | View, customise or turn off your terminal welcome | `motd --edit` |

Run `<command> --help` for options. Archive support depends on which extractors are installed; `jd` and `jdir` need `wget`.

**Three quick examples:**

```bash
sysinfo --table             # a different layout for your system snapshot
netinfo --kv                # predictable key=value lines for scripts
extract backup.tar.gz       # unpack without remembering tar flags
```

Some handy switches:

```bash
sysinfo --box               # bordered dashboard (also --table or --stacked)
sysinfo --plain             # no terminal colour codes
netinfo --stacked           # narrow-terminal-friendly layout
extract --list archive.zip  # inspect an archive before unpacking it
flushdns --status           # see what DNS cache service can be detected
motd --off                  # stop showing the startup message
```

## See it in action

These are **actual ShellMate terminal screenshots** from the project, not interface mock-ups. Click any image to view it at full size.

<p align="center">
  <a href="docs/screenshots/mac_motd.png"><img src="docs/screenshots/mac_motd.png" alt="ShellMate's welcome message and command list in macOS Terminal" width="820"></a>
  <br><sub>macOS · Bash welcome and built-in commands</sub>
</p>

<table>
  <tr>
    <td align="center" width="50%">
      <a href="docs/screenshots/gnome_term.png"><img src="docs/screenshots/gnome_term.png" alt="ShellMate sysinfo running in GNOME Terminal on Linux"></a>
      <br><sub>Linux · GNOME Terminal · system information</sub>
    </td>
    <td align="center" width="50%">
      <a href="docs/screenshots/windows_wsl.png"><img src="docs/screenshots/windows_wsl.png" alt="ShellMate running in Bash on Windows Subsystem for Linux"></a>
      <br><sub>Windows · WSL · Bash inside Windows Terminal</sub>
    </td>
  </tr>
</table>

<!-- Optional artwork slot: add the finished Ruby + ShellMate banner to docs/branding/
     and link it here after the image has been committed. -->

## Where it works

ShellMate targets **Bash 3.2+**, using portable shell code and OS-specific checks. There is a difference between a platform having a test target and being individually certified on every release:

| Environment | Coverage | Notes |
| --- | --- | --- |
| **macOS** | Supported Bash target; real-Mac checks are manual | Works with system `/bin/bash` 3.2; zsh is not the target shell. |
| **Ubuntu** | Automated disposable-container test target | The Linux baseline. |
| **Debian** | Automated disposable-container test target; best-effort distro support | Tested with a slim image to expose missing optional tools. |
| **Fedora** | Automated disposable-container test target; best-effort distro support | Includes the non-login Bash setup path. |
| **Windows + WSL** | WSL-specific regression checks and a real-world screenshot | Runs inside Linux Bash, not native Windows shells. |
| **Other Linux** | Best effort; not each distro individually tested | Intended for common Bash environments, including RHEL-family, Arch, openSUSE and Alpine, subject to system tools. |

The Linux test suite runs in **Ubuntu 24.04, Debian 12, Fedora 41 and an Alpine-based Bash 3.2 image**. Bash 3.2 testing catches incompatible syntax; it is **not** a substitute for testing Apple's BSD userland on a real Mac.

Linux dependency bootstrapping recognises `apt`, `dnf`, `yum`, `pacman`, `zypper` and `apk`; macOS uses Homebrew for optional packages. That does not mean every distribution has an identical test guarantee.

See the [compatibility contract](docs/v2.0/compatibility_contract.md) for the precise supported/best-effort distinction.

### WSL: a small detail that matters

Files on Windows drives such as `/mnt/c` sometimes appear executable to Linux, making a normal coloured `ls` list look as if *everything* is a program. ShellMate detects those WSL mounts and makes regular files readable and directories easy to spot, without changing Linux-drive listings.

Prefer blue directories instead of the default bright yellow?

```bash
export BASH_PROFILE_WSL_DIR_COLOR="01;34"
```

It's optional, and it doesn't require changing your Windows settings.

## Your welcome message, your way

The first **three** interactive Bash sessions introduce ShellMate's commands, then the welcome stops automatically. Bring it back any time:

```bash
motd              # show the welcome
motd --edit       # write your own login message
motd --off        # disable it
motd --on         # enable it again
```

Your custom message is plain text at `~/.config/my-mac-bash-profile/motd`. It is displayed as text, **not executed as shell code**.

## Sensible defaults, room to tinker

ShellMate uses small Bash modules in `profile.d/` rather than a large plugin framework. Features are loaded when Bash starts; the expensive work happens when you actually run a helper. It avoids network calls or package installation merely from sourcing your profile.

### Use only the bits you want

Try a fresh login Bash with a feature disabled:

```bash
BASH_PROFILE_MODULES_DISABLE="netinfo" bash -l
```

Or load just a few modules:

```bash
BASH_PROFILE_MODULES_ENABLE="sysinfo extract" bash -l
```

These variables must be set **before** ShellMate loads; place persistent choices in your shell's early startup configuration. You can also keep per-machine aliases and overrides in:

- `profile.d/local.sh` (ignored by Git)
- `~/.config/my-mac-bash-profile/local.sh`

Local overrides are loaded last. For more, read [configuration and modules](docs/v2.0/config_and_modules.md).

### Script-friendly output

`sysinfo` and `netinfo` offer stable `--kv` output, with one `key=value` per line instead of colours or decorative tables:

```bash
sysinfo --kv
netinfo --kv

local_ip=$(netinfo --kv | awk -F= '/^local_ip=/ {print $2}')
printf 'Local IP: %s\n' "$local_ip"
```

The field names and ordering are documented in the [helper contract](docs/v2.0/helper_contract.md).

### For Mac power users

Two extra helpers are available on macOS:

- `cdf` — switch to the folder shown in the frontmost Finder window.
- `gosu` — launch a Terminal tab running `sudo -s` (depends on AppleScript/Terminal settings).

## Updates, backups and removal

To update an installation, rerun the **same one-line release installer**. By default the installer backs up what it replaces, including the existing ShellMate installation.

To review changes before applying them:

```bash
cd ShellMate
bash scripts/install.sh --repo "$(pwd)" --dry-run
```

To remove ShellMate, first check where your login profile points:

```bash
readlink ~/.bash_profile
```

**Only if** it points to the ShellMate installation, remove that symlink. Then restore any saved `~/.bash_profile.bak.*` backup you want to keep, remove the ShellMate-managed block between the `my-mac-bash-profile` markers in `~/.bashrc` (Linux), and remove `~/.my-mac-bash-profile` if no longer needed. Avoid deleting a `~/.bash_profile` you have since customised.

## Help! My terminal isn't behaving

**Nothing is loading?** Confirm you're in Bash:

```bash
echo "$BASH_VERSION"
```

If that's empty, launch `bash -l`. On Linux, remember that login and non-login Bash read different startup files; the installer normally handles that.

**Want to skip all ShellMate modules while investigating?**

```bash
BASH_PROFILE_SAFE_MODE=1 bash -l
```

**Want to inspect exactly what loaded?**

```bash
mm_bash_profile_doctor
```

There is also the nuclear *Bash-only* fallback `bash --noprofile --norc`, which does not read your startup files. A mistaken `exit`, `logout` or `set -e` in a sourced module is guarded so it does not unexpectedly close the user's shell.

For problems, suggestions or bug reports, open a [GitHub issue](https://github.com/macg4dave/ShellMate/issues).

## For the tinkerers

Everything is ordinary Bash. No runtime package manager, no extra service and no hidden configuration database.

```text
.bash_profile            Bash entry point and module loader
profile.d/               Small cross-platform and OS-specific helpers
scripts/install.sh       Installer, dry-run and backups
scripts/bootstrap-*.sh   Optional system-tool setup
tests/                   Smoke, regression, safety and contract tests
docker/                  Throwaway distro test environments
docs/v2.0/               Compatibility, helper and configuration contracts
```

From a cloned checkout:

```bash
make lint                          # ShellCheck (install it first)
make test                          # Bash smoke, regression, safety and contract tests
make docker-test                   # Ubuntu, Debian, Fedora and Bash 3.2
make docker-test TARGETS="debian bash32"
DOCKER=podman make docker-test     # prefer Podman? No problem
make hooks                         # run lint + tests before each commit
```

The container tests run a **real install in a disposable HOME** and check that a new Bash login session can load the helpers. They do **not** run automatically as GitHub test CI on every push; the GitHub workflow currently publishes tagged releases. Check the [release process](docs/v2.0/release_process.md) and [changelog](docs/v1.0/CHANGELOG.md) for details.

**Contributions welcome:** keep changes Bash 3.2-compatible, safe to source and friendly when optional tools are missing. Read [AGENTS.md](AGENTS.md) and the [helper contract](docs/v2.0/helper_contract.md) before adding a command.

---

<p align="center">
  <strong>ShellMate</strong> — useful tools, familiar Bash, less faffing about.<br>
  <sub>With Ruby keeping an eye on the terminal.</sub>
</p>
