#!/usr/bin/env bash
# Behaviour checks for bugs that have bitten before (extract, pathinfo, loader).
# Each check uses only tools it guards for, so it runs on slim/busybox images.

set -euo pipefail

repo_root="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp_home="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_home"
}
trap cleanup EXIT

export HOME="$tmp_home"
export XDG_CACHE_HOME="$tmp_home/.cache"
export XDG_CONFIG_HOME="$tmp_home/.config"
export XDG_STATE_HOME="$tmp_home/.local/state"
mkdir -p "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
export NETINFO_EXTERNAL_IP=0

fail() {
  echo "regressions: $*" >&2
  exit 1
}

# shellcheck source=/dev/null
source "$repo_root/profile.d/10-common.sh"
# shellcheck source=/dev/null
source "$repo_root/profile.d/extract.sh"
# shellcheck source=/dev/null
source "$repo_root/profile.d/pathinfo.sh"

work="$tmp_home/work"
mkdir -p "$work/src/sub"
cd "$work"
echo original > src/sub/a.txt
(cd src && tar czf ../t.tar.gz sub)

# --- extract: tar ------------------------------------------------------------

# The [dest] positional must be honoured.
extract t.tar.gz outdir >/dev/null || fail "extract t.tar.gz outdir failed"
[[ -f outdir/sub/a.txt ]] || fail "extract ignored the [dest] argument"

# Quiet unless -v (verbose used to be always on).
out="$(extract t.tar.gz quiet 2>&1)" || fail "extract into fresh dir failed"
[[ -z "$out" ]] || fail "extract printed output without -v: $out"

# No clobbering without --force; runtime failure exits 1.
echo changed > quiet/sub/a.txt
rc=0
extract t.tar.gz quiet >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 1 ]] || fail "extract over existing files exited $rc, expected 1"
[[ "$(cat quiet/sub/a.txt)" == changed ]] || fail "extract overwrote a file without --force"

# --list and unsupported formats must not create directories.
extract --list t.tar.gz >/dev/null || fail "extract --list failed"
[[ ! -e t ]] || fail "extract --list created a destination directory"
: > unknown.weird
extract unknown.weird >/dev/null 2>&1 && fail "extract accepted an unsupported format"
[[ ! -e unknown ]] || fail "extract created a directory for an unsupported format"

rc=0
extract a b c >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || fail "extract with too many arguments exited $rc, expected 2"

# --- extract: zip (unzip -v used to turn extraction into a listing) -----------

if has_cmd zip && has_cmd unzip; then
  (cd src && zip -qr ../t.zip sub)
  extract t.zip >/dev/null || fail "extract t.zip failed"
  [[ "$(cat t/sub/a.txt 2>/dev/null)" == original ]] || fail "extract t.zip did not extract"

  echo changed > t/sub/a.txt
  extract t.zip >/dev/null 2>&1 || true
  [[ "$(cat t/sub/a.txt)" == changed ]] || fail "extract t.zip overwrote without --force"
  extract --force t.zip >/dev/null || fail "extract --force t.zip failed"
  [[ "$(cat t/sub/a.txt)" == original ]] || fail "extract --force t.zip did not overwrite"

  # Path traversal is refused unless forced.
  (cd src/sub && zip -q ../../evil.zip ../sub/a.txt)
  extract evil.zip >/dev/null 2>&1 && fail "extract accepted a zip with ../ paths"
fi

# --- extract: single-file formats ---------------------------------------------

if has_cmd gzip; then
  echo hello > single.txt
  gzip -c single.txt > single.txt.gz
  extract single.txt.gz single_out >/dev/null || fail "extract .gz failed"
  [[ "$(cat single_out/single.txt)" == hello ]] || fail "extract .gz wrong content"
  extract single.txt.gz single_out >/dev/null 2>&1 && fail "extract .gz overwrote without --force"
fi

if has_cmd compress; then
  echo hello-z > zfile
  compress -c zfile > zfile.Z
  extract zfile.Z zout >/dev/null || fail "extract .Z failed (lowercased name never matched *.Z before)"
  [[ "$(cat zout/zfile)" == hello-z ]] || fail "extract .Z wrong content"
fi

# --- pathinfo: a trailing ':' (current directory) must be reported -------------

lines="$(PATH="/usr/bin:/bin:" pathinfo | wc -l | tr -d '[:space:]')"
[[ "$lines" -eq 3 ]] || fail "pathinfo dropped the trailing empty PATH entry ($lines lines, expected 3)"

# --- loader: PATH/alias block runs after 10-common.sh -------------------------

# Only existing dirs may be prepended (this used to run before path helpers existed).
# shellcheck disable=SC2016  # expanded by the inner shell, on purpose
loaded_path="$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash --noprofile --norc -c \
  'source "$1/.bash_profile" >/dev/null 2>&1; printf %s "$PATH"' _ "$repo_root")"
IFS=':' read -r -a path_parts <<< "$loaded_path"
for d in "${path_parts[@]}"; do
  [[ -z "$d" || -d "$d" ]] || fail "profile prepended a non-existent PATH entry: $d"
done

# --- sysinfo: internals stay private; parsers handle real macOS output ----------

(
  # shellcheck source=/dev/null
  source "$repo_root/profile.d/sysinfo.sh"
  sysinfo --kv >/dev/null
  for name in main find_os human_bytes print_terminal sysinfo_usage mac_get_ram linux_get_cpu; do
    declare -F "$name" >/dev/null && fail "sysinfo leaked function '$name' into the shell"
  done
  for name in os_name ram_total uptime_load network_down which_os; do
    [[ -z "${!name+x}" ]] || fail "sysinfo leaked variable '$name' into the shell"
  done

  diskutil_out="$(_sysinfo_parse_diskutil <<'X'
   Volume Name:               Macintosh HD
   Container Total Space:     494.4 GB (494384795648 Bytes) (exactly 965595304 512-Byte-Units)
   Container Free Space:      301.2 GB (301234567168 Bytes) (exactly 588348764 512-Byte-Units)
X
)"
  [[ "$diskutil_out" == $'Macintosh HD\t494.4 GB\t193.2 GB\t301.2 GB' ]] || fail "diskutil parse: $diskutil_out"

  # Address column blank for lo0; en01 must not match en0.
  netstat_out="$(_sysinfo_parse_netstat_ib en0 <<'X'
Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll
lo0        16384 <Link#1>                         84471     0   14569031    84471     0   14569031     0
en01       1500  <Link#12>   a4:83:e7:12:34:57      1     0          1        1     0          1     0
en0        1500  <Link#11>   a4:83:e7:12:34:56  9123456     0 9876543210  4567890     0  123456789     0
X
)"
  [[ "$netstat_out" == "9876543210 123456789" ]] || fail "netstat -ib parse: $netstat_out"

  top_out="$(printf '%s\n' 'CPU usage: 25.0% user, 50.0% sys, 25.0% idle' 'CPU usage: 4.29% user, 8.58% sys, 87.12% idle' | _sysinfo_parse_top_cpu)"
  [[ "$top_out" == "4.29 8.58 87.12" ]] || fail "top parse (should use the last sample): $top_out"

  [[ "$(echo '{ 1.23 1.45 1.67 }' | _sysinfo_norm_load)" == "1.23, 1.45, 1.67" ]] || fail "vm.loadavg parse"
  [[ "$(_sysinfo_fmt_duration 90061)" == "up 1 day, 1 hour, 1 minute" ]] || fail "uptime duration format"
  [[ "$(_sysinfo_fmt_uptime_short 'up 2 weeks, 1 day, 3 hours, 1 minute')" == "2w 1d 3h 1m" ]] || fail "uptime short format"

  # awk fallback (no numfmt, e.g. stock macOS) must match numfmt's output.
  # shellcheck disable=SC2317,SC2329  # override, called by the sourced code
  _sysinfo_has_cmd() { [[ "$1" != numfmt ]] && command -v "$1" >/dev/null 2>&1; }
  [[ "$(_sysinfo_human_bytes 17179869184)" == "16.00GB" ]] || fail "human_bytes fallback 16GiB"
  [[ "$(_sysinfo_human_bytes 1500)" == "1.47KB" ]] || fail "human_bytes fallback rounds up like numfmt"
  [[ "$(_sysinfo_human_bytes 1048575)" == "1.00MB" ]] || fail "human_bytes fallback carries into next unit"
)

# --- netinfo: value shapes and untrusted network data ---------------------------

(
  # shellcheck source=/dev/null
  source "$repo_root/profile.d/netinfo.sh"
  lip="$(netinfo --kv | sed -n 's/^local_ip=//p')"
  [[ "$lip" == "N/A" || "$lip" != */* ]] || fail "netinfo local_ip includes a /prefix: $lip"

  _netinfo_is_ip 203.0.113.7 || fail "is_ip rejected IPv4"
  _netinfo_is_ip 2001:db8::1 || fail "is_ip rejected IPv6"
  _netinfo_is_ip '<html>Login</html>' && fail "is_ip accepted HTML"
  [[ "$(_netinfo_sanitize $'evil\e]0;x\ahost')" == "evil]0;xhost" ]] || fail "sanitize kept control characters"

  utun="$(_netinfo_parse_utun_ifconfig <<'X' | _netinfo_join_lines
utun0: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
	inet6 fe80::1%utun0 prefixlen 64 scopeid 0x10
utun4: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1280
	inet 100.101.102.103 --> 100.101.102.103 netmask 0xffffffff
	inet 10.0.0.2 --> 10.0.0.2 netmask 0xffffffff
X
)"
  [[ "$utun" == "utun4" ]] || fail "macOS VPN detection should skip IPv6-only utuns: $utun"
)

# --- motd: welcome shows N times in interactive shells, then stops -------------

motd_home="$tmp_home/motd-home"
mkdir -p "$motd_home"
motd_login() {
  # Interactive shell (-i) without a tty; drop bash's job-control noise.
  # shellcheck disable=SC2016  # expanded by the inner shell, on purpose
  env -i HOME="$motd_home" PATH="$PATH" TERM=dumb "$@" \
    bash --noprofile --norc -i -c 'source "$1/.bash_profile"; eval "${2:-:}"' _ "$repo_root" "${MOTD_CMD:-}" 2>&1 \
    | grep -vE 'job control|terminal process group' || true
}
for n in 1 2 3; do
  motd_login | grep -q "$n of 3" || fail "motd welcome missing on interactive shell $n"
done
[[ -z "$(motd_login)" ]] || fail "motd welcome still shown after 3 shells"
# shellcheck disable=SC2016  # expanded by the inner shell, on purpose
[[ -z "$(env -i HOME="$motd_home/fresh" PATH="$PATH" bash --noprofile --norc -c 'source "$1/.bash_profile"' _ "$repo_root" 2>&1)" ]] \
  || fail "motd printed in a non-interactive shell"
[[ -z "$(motd_login BASH_PROFILE_MOTD=0 HOME="$motd_home/env-off")" ]] || fail "BASH_PROFILE_MOTD=0 did not silence motd"

# `motd --edit` saved untouched: the starter is all # notes, so no message.
MOTD_CMD='EDITOR=true motd --edit' motd_login >/dev/null
starter="$motd_home/.config/my-mac-bash-profile/motd"
[[ -s "$starter" ]] || fail "motd --edit did not create a starter file"
grep -q 'motd --off' "$starter" || fail "motd starter file does not explain how to turn it off"
[[ -z "$(motd_login)" ]] || fail "untouched motd starter file was shown as a message"
[[ "$(MOTD_CMD='motd' motd_login | head -n 1)" == "Welcome to ShellMate"* ]] \
  || fail "motd with an untouched starter file should show the welcome"

printf '# a note\n\ncustom hello\n# another note\n\n' > "$starter"
[[ "$(motd_login)" == "custom hello" ]] || fail "motd showed # notes or blank padding"

mkdir -p "$motd_home/.config/my-mac-bash-profile"
printf 'custom hello' > "$motd_home/.config/my-mac-bash-profile/motd"
[[ "$(motd_login)" == "custom hello" ]] || fail "custom motd not shown at login"
MOTD_CMD='motd --off' motd_login >/dev/null
[[ -z "$(motd_login)" ]] || fail "motd --off did not stop the login message"
MOTD_CMD='motd --on' motd_login >/dev/null
[[ "$(motd_login)" == "custom hello" ]] || fail "motd --on did not bring the message back"

# Box layout: every line the same width; art only when there is room; no
# colour codes when not writing to a terminal.
(
  # shellcheck source=/dev/null
  source "$repo_root/profile.d/motd.sh"
  wide="$(COLUMNS=80 TERM=xterm LC_ALL=C motd)"
  [[ "$wide" == *"<___/\___>"* ]] || fail "motd box is missing the seashell art at 80 columns"
  [[ "$wide" != *$'\033'* ]] || fail "motd printed colour codes to a non-terminal"
  widths="$(printf '%s\n' "$wide" | awk '{print length($0)}' | sort -u | tr -d '[:space:]')"
  [[ "$widths" == 72 ]] || fail "motd box lines have uneven widths: $widths"
  narrow="$(COLUMNS=50 TERM=xterm LC_ALL=C motd)"
  [[ "$narrow" != *"<___/"* && "$narrow" == "+---"*"Welcome to ShellMate"* ]] || fail "motd at 50 columns should be a box without art"
  [[ "$(COLUMNS=30 TERM=xterm motd | head -n 1)" == "Welcome to ShellMate"* ]] || fail "motd at 30 columns should be plain"
)

# --- load guard: a bad local override must not close the terminal ---------------

guard_home="$tmp_home/guard-home"
mkdir -p "$guard_home/.config/my-mac-bash-profile"
guard_local="$guard_home/.config/my-mac-bash-profile/local.sh"
guard_login() {
  # shellcheck disable=SC2016  # expanded by the inner shell, on purpose
  env -i HOME="$guard_home" PATH="$PATH" TERM=dumb BASH_PROFILE_MOTD=0 "$@" \
    bash --noprofile --norc -i -c 'source "$1/.bash_profile"; echo ALIVE; [[ $- == *e* ]] && echo ERREXIT; echo "VAR=${MY_VAR:-}"; type -t exit' _ "$repo_root" 2>&1 \
    | grep -vE 'job control|terminal process group' || true
}
for body in 'exit' 'exit 1' 'logout' 'set -e; false' 'set -euo pipefail; false' 'set -o errexit; false'; do
  printf '%s\n' "$body" > "$guard_local"
  out="$(guard_login)"
  [[ "$out" == *ALIVE* ]] || fail "local.sh containing '$body' killed the shell"
  [[ "$out" != *ERREXIT* ]] || fail "local.sh containing '$body' left set -e on"
  [[ "$out" == *"shellmate: ignored"* ]] || fail "no warning for '$body' in local.sh"
  [[ "$(printf '%s\n' "$out" | tail -n 1)" == builtin ]] || fail "guard functions left behind after '$body'"
done
printf 'declare -x MY_VAR=kept\n' > "$guard_local"
[[ "$(guard_login)" == *"VAR=kept"* ]] || fail "declare in local.sh no longer reaches the shell"
printf 'exit\n' > "$guard_local"
out="$(guard_login BASH_PROFILE_SAFE_MODE=1)"
[[ "$out" == *"safe mode"* && "$out" != *"ignored 'exit'"* ]] || fail "BASH_PROFILE_SAFE_MODE=1 still loaded local.sh"
rm -f "$guard_local"

# --- motd: the message file is text only, cleaned, and size-capped --------------

(
  # shellcheck source=/dev/null
  source "$repo_root/profile.d/motd.sh"
  msg="$tmp_home/motd-msg"
  # shellcheck disable=SC2016  # a literal $(...) on purpose: it must never run
  printf 'hi \033[2J\033(0there\r\n$(touch %s/pwned)\ttab\n' "$tmp_home" > "$msg"
  _motd_read_message "$msg" || fail "motd message not read"
  joined="$(printf '%s|' "${_MOTD_MSG[@]}")"
  [[ "$joined" != *[[:cntrl:]]* ]] || fail "motd message kept control characters"
  # shellcheck disable=SC2016  # a literal $(...) on purpose: it must never run
  [[ "$joined" == *'$(touch'* && ! -e "$tmp_home/pwned" ]] || fail "motd message was executed"
  seq 1 100000 > "$msg"
  _motd_read_message "$msg"
  [[ ${#_MOTD_MSG[@]} -eq 40 ]] || fail "motd message not capped at 40 lines (${#_MOTD_MSG[@]})"
  rm -f "$msg"
  mkdir "$msg"
  _motd_read_message "$msg" 2>/dev/null && fail "motd treated a directory as a message"
  rmdir "$msg"
)

echo "regressions: ok"
