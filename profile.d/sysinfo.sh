#!/usr/bin/env bash

# This file is intended to be *sourceable* by `.bash_profile` (to provide a
# `sysinfo` helper) and also runnable directly (`./sysinfo.sh`).
#
# IMPORTANT: do not auto-run on source.

# shellcheck shell=bash

_sysinfo_has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Measurements. Everything here is prefixed _sysinfo_ because this file is
# sourced into the user's interactive shell; _sysinfo_reset runs before each
# collection so no stale values leak between runs.
_sysinfo_reset() {
    _sysinfo_which_os=""   # 1 = macOS, 2 = Linux
    _sysinfo_os_name="N/A"
    _sysinfo_os_ver="N/A"
    _sysinfo_net_iface=""
    _sysinfo_startup_name="N/A"
    _sysinfo_startup_size="N/A"
    _sysinfo_startup_used="N/A"
    _sysinfo_startup_free="N/A"
    _sysinfo_uptime_time="N/A"
    _sysinfo_uptime_load="N/A"
    _sysinfo_cpu_used_user="N/A"
    _sysinfo_cpu_used_sys="N/A"
    _sysinfo_cpu_used_idle="N/A"
    _sysinfo_network_down="N/A"
    _sysinfo_network_up="N/A"
    _sysinfo_ram_total="N/A"
    _sysinfo_ram_used="N/A"
    _sysinfo_ram_free="N/A"
}

_sysinfo_find_os() {
    _sysinfo_os_name="$(uname 2>/dev/null || echo 'Unknown')"
    case "$_sysinfo_os_name" in
        Darwin)
            _sysinfo_which_os="1"
            if _sysinfo_has_cmd sw_vers; then
                _sysinfo_os_ver="$(sw_vers -productVersion 2>/dev/null || echo 'N/A')"
            fi
            ;;
        Linux)
            _sysinfo_which_os="2"
            _sysinfo_os_ver="$(uname -r 2>/dev/null || echo 'N/A')"  # kernel version
            ;;
        *)
            echo "sysinfo: unsupported OS: $_sysinfo_os_name" >&2
            return 1
            ;;
    esac
}

# Bytes -> IEC string with 2 decimals (e.g. 16.00GB). Uses numfmt (GNU
# coreutils) when present; macOS lacks it by default, so the awk fallback
# mimics numfmt's output, including its round-up behaviour.
_sysinfo_human_bytes() {
    local bytes="$1"
    if [[ -z "$bytes" || "$bytes" == "0" ]]; then
        echo "0B"
        return 0
    fi
    if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
        echo "N/A"
        return 0
    fi
    if _sysinfo_has_cmd numfmt && numfmt --to=iec --suffix=B --format="%.2f" "$bytes" 2>/dev/null; then
        return 0
    fi
    awk -v b="$bytes" 'BEGIN {
        split("B KB MB GB TB PB EB", unit, " ")
        v = b + 0; i = 1
        if (v < 1024) { printf "%.2fB\n", v; exit }
        while (v >= 1024 && i < 7) { v /= 1024; i++ }
        c = v * 100; r = int(c); if (r < c) r++
        v = r / 100
        if (v >= 1024 && i < 7) { v /= 1024; i++ }
        printf "%.2f%s\n", v, unit[i]
    }'
}

# Interface byte counter -> human string (N/A when unknown).
_sysinfo_net_bytes() {
    local v="$1"
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        _sysinfo_human_bytes "$v"
    else
        echo "N/A"
    fi
}

# Seconds -> "up 3 days, 4 hours, 5 minutes" (same shape as `uptime -p`).
_sysinfo_fmt_duration() {
    local secs="$1"
    [[ "$secs" =~ ^[0-9]+$ ]] || { echo "N/A"; return 0; }
    awk -v s="$secs" 'BEGIN {
        d = int(s / 86400); h = int((s % 86400) / 3600); m = int((s % 3600) / 60)
        out = ""
        if (d > 0) out = out d (d == 1 ? " day" : " days")
        if (h > 0) out = out (out == "" ? "" : ", ") h (h == 1 ? " hour" : " hours")
        if (m > 0 || out == "") out = out (out == "" ? "" : ", ") m (m == 1 ? " minute" : " minutes")
        print "up " out
    }'
}

# "1.0 2.0 3.0", "{ 1.0 2.0 3.0 }" or "1.0, 2.0, 3.0" (stdin) -> "1.0, 2.0, 3.0".
_sysinfo_norm_load() {
    awk '{
        gsub(/[{},]/, " ")
        n = 0; out = ""
        for (i = 1; i <= NF && n < 3; i++) {
            if ($i ~ /^[0-9]+([.,][0-9]+)?$/) { out = out (n ? ", " : "") $i; n++ }
        }
        if (n == 3) print out
        exit
    }'
}

# --- macOS ---------------------------------------------------------------------

_sysinfo_mac_ram() {
    _sysinfo_has_cmd sysctl && _sysinfo_has_cmd vm_stat || return 0

    local total_bytes vm page_size
    total_bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
    vm="$(vm_stat 2>/dev/null || true)"
    page_size="$(printf '%s\n' "$vm" | awk '/page size of/ {gsub("[^0-9]","",$0); print $0; exit}')"
    [[ "$total_bytes" =~ ^[0-9]+$ && "$page_size" =~ ^[0-9]+$ ]] || return 0

    # vm_stat reports page counts with trailing periods.
    local counts free speculative active inactive wired compressed
    counts="$(printf '%s\n' "$vm" | awk '
        function n(s) { gsub(/[^0-9]/, "", s); return s + 0 }
        /^Pages free:/                   { f = n($NF) }
        /^Pages speculative:/            { sp = n($NF) }
        /^Pages active:/                 { a = n($NF) }
        /^Pages inactive:/               { ia = n($NF) }
        /^Pages wired down:/             { w = n($NF) }
        /^Pages occupied by compressor:/ { c = n($NF) }
        END { print f + 0, sp + 0, a + 0, ia + 0, w + 0, c + 0 }')"
    read -r free speculative active inactive wired compressed <<< "$counts"

    _sysinfo_ram_total="$(_sysinfo_human_bytes "$total_bytes")"
    _sysinfo_ram_used="$(_sysinfo_human_bytes $(( (active + inactive + wired + compressed) * page_size )))"
    _sysinfo_ram_free="$(_sysinfo_human_bytes $(( (free + speculative) * page_size )))"
}

# Parse `diskutil info /` (stdin) -> "name<TAB>size<TAB>used<TAB>free".
# Size/free are shown as diskutil prints them (decimal units, e.g. "494.4 GB");
# used is computed from the exact byte counts and printed the same way.
_sysinfo_parse_diskutil() {
    awk '
      function val(s)   { sub(/^[^:]*:[[:space:]]*/, "", s); return s }
      function shown(s) { s = val(s); sub(/[[:space:]]*\(.*/, "", s); return s }
      function bytes(s) { if (match(s, /\([0-9]+ Bytes\)/)) return substr(s, RSTART + 1, RLENGTH - 8); return "" }
      function dec(b,   u, i) {
          split("B KB MB GB TB PB", u, " "); i = 1
          while (b >= 1000 && i < 6) { b /= 1000; i++ }
          return sprintf("%.1f %s", b, u[i])
      }
      /^[[:space:]]*Volume Name:/            { name = val($0) }
      /^[[:space:]]*Container Total Space:/  { cts = shown($0); ctb = bytes($0) }
      /^[[:space:]]*Container Free Space:/   { cfs = shown($0); cfb = bytes($0) }
      /^[[:space:]]*(Volume Total Space|Total Size):/ { if (vts == "") { vts = shown($0); vtb = bytes($0) } }
      /^[[:space:]]*(Volume Free Space|Volume Available Space):/ { if (vfs == "") { vfs = shown($0); vfb = bytes($0) } }
      END {
          # APFS: the container is what fills up; older HFS+ only has volume fields.
          if (cts != "") { ts = cts; tb = ctb } else { ts = vts; tb = vtb }
          if (cfs != "") { fs = cfs; fb = cfb } else { fs = vfs; fb = vfb }
          used = (tb != "" && fb != "") ? dec(tb - fb) : ""
          printf "%s\t%s\t%s\t%s\n", (name == "" ? "N/A" : name), (ts == "" ? "N/A" : ts), (used == "" ? "N/A" : used), (fs == "" ? "N/A" : fs)
      }'
}

_sysinfo_mac_disk() {
    _sysinfo_has_cmd diskutil || return 0
    local name size used free
    IFS=$'\t' read -r name size used free < <(diskutil info / 2>/dev/null | _sysinfo_parse_diskutil)
    _sysinfo_startup_name="${name:-N/A}"
    _sysinfo_startup_size="${size:-N/A}"
    _sysinfo_startup_used="${used:-N/A}"
    _sysinfo_startup_free="${free:-N/A}"
}

# Parse `netstat -ib` (stdin) -> "<rx_bytes> <tx_bytes>" for the interface's
# <Link#N> row. Columns are found from the header and counted from the END of
# the row, because the Address column is blank for some interfaces.
_sysinfo_parse_netstat_ib() {
    awk -v iface="$1" '
      NR == 1 {
          for (i = 1; i <= NF; i++) {
              if ($i == "Ibytes") { ib = NF - i; have_ib = 1 }
              if ($i == "Obytes") { ob = NF - i; have_ob = 1 }
          }
          next
      }
      have_ib && have_ob && $1 == iface && $3 ~ /^<Link/ { print $(NF - ib), $(NF - ob); exit }'
}

_sysinfo_mac_net() {
    _sysinfo_has_cmd netstat || return 0
    local iface=""
    if _sysinfo_has_cmd route; then
        iface="$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')"
    fi
    _sysinfo_net_iface="${iface:-en0}"

    local rx tx
    read -r rx tx < <(netstat -ib 2>/dev/null | _sysinfo_parse_netstat_ib "$_sysinfo_net_iface")
    _sysinfo_network_down="$(_sysinfo_net_bytes "${rx:-}")"
    _sysinfo_network_up="$(_sysinfo_net_bytes "${tx:-}")"
}

# Parse a top "CPU usage: 5.1% user, 10.2% sys, 84.6% idle" line (stdin) -> "u s i".
_sysinfo_parse_top_cpu() {
    awk '/CPU usage/ {
        for (i = 1; i < NF; i++) {
            v = $i; sub(/%$/, "", v)
            if ($(i + 1) ~ /^user/) u = v
            if ($(i + 1) ~ /^sys/)  s = v
            if ($(i + 1) ~ /^idle/) d = v
        }
        line = u " " s " " d
    }
    END { if (u != "" && s != "" && d != "") print line }'
}

_sysinfo_mac_cpu() {
    _sysinfo_has_cmd top || return 0
    # top's first sample covers an undefined interval; take the second, 1s later.
    local u s i
    read -r u s i < <(top -l 2 -n 0 -s 1 2>/dev/null | _sysinfo_parse_top_cpu)
    [[ -n "${i:-}" ]] || return 0
    _sysinfo_cpu_used_user="$u"
    _sysinfo_cpu_used_sys="$s"
    _sysinfo_cpu_used_idle="$i"
}

_sysinfo_mac_uptime() {
    local boot now load
    if _sysinfo_has_cmd sysctl; then
        # "{ sec = 1700000000, usec = 0 } Mon Nov 13 ..."
        boot="$(sysctl -n kern.boottime 2>/dev/null | awk -F'[ ,]+' '{for (i = 1; i < NF; i++) if ($i == "sec") {print $(i + 2); exit}}')"
        now="$(date +%s 2>/dev/null || true)"
        if [[ "$boot" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ && "$now" -ge "$boot" ]]; then
            _sysinfo_uptime_time="$(_sysinfo_fmt_duration $((now - boot)))"
        fi
        load="$(sysctl -n vm.loadavg 2>/dev/null | _sysinfo_norm_load)"
    fi
    if [[ -z "${load:-}" ]] && _sysinfo_has_cmd uptime; then
        # macOS says "load averages:", Linux "load average:".
        load="$(uptime 2>/dev/null | sed -n 's/.*load averages*: *//p' | _sysinfo_norm_load)"
    fi
    _sysinfo_uptime_load="${load:-N/A}"
}

# --- Linux ---------------------------------------------------------------------

_sysinfo_linux_ram() {
    local total_kb="" avail_kb=""
    if [[ -r /proc/meminfo ]]; then
        total_kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
        avail_kb="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
    fi

    local total_b avail_b
    if [[ -n "$total_kb" && -n "$avail_kb" ]]; then
        total_b=$((total_kb * 1024))
        avail_b=$((avail_kb * 1024))
    elif _sysinfo_has_cmd free; then
        # Fallback: best-effort using `free -b`
        total_b="$(free -b 2>/dev/null | awk '/^Mem:/ {print $2; exit}')"
        avail_b="$(free -b 2>/dev/null | awk '/^Mem:/ {print $7; exit}')"
    fi
    [[ "${total_b:-}" =~ ^[0-9]+$ && "${avail_b:-}" =~ ^[0-9]+$ ]] || return 0

    _sysinfo_ram_total="$(_sysinfo_human_bytes "$total_b")"
    _sysinfo_ram_free="$(_sysinfo_human_bytes "$avail_b")"
    _sysinfo_ram_used="$(_sysinfo_human_bytes $((total_b - avail_b)))"
}

_sysinfo_linux_disk() {
    _sysinfo_startup_name="/"
    _sysinfo_has_cmd df || return 0
    local size used free
    read -r size used free < <(df -h / 2>/dev/null | awk 'NR==2 {print $2, $3, $4}')
    _sysinfo_startup_size="${size:-N/A}"
    _sysinfo_startup_used="${used:-N/A}"
    _sysinfo_startup_free="${free:-N/A}"
}

# Detect the primary network interface (default route), falling back to the
# first non-loopback interface in /proc/net/dev.
_sysinfo_linux_detect_iface() {
    local iface=""
    if _sysinfo_has_cmd ip; then
        iface="$(ip route 2>/dev/null | awk '/^default/ {for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')"
    fi
    # Fallback for restricted environments where `ip` can't query netlink.
    if [[ -z "$iface" && -r /proc/net/route ]]; then
        iface="$(awk '$2 == "00000000" {print $1; exit}' /proc/net/route 2>/dev/null)"
    fi
    if [[ -n "$iface" && -r /proc/net/dev ]] && ! awk -v iface="$iface" 'NR>2 {sub(/^[[:space:]]+/, ""); split($0, a, ":"); if (a[1] == iface) found = 1} END {exit found ? 0 : 1}' /proc/net/dev; then
        iface=""
    fi
    if [[ -z "$iface" && -r /proc/net/dev ]]; then
        iface="$(awk 'NR>2 {sub(/^[[:space:]]+/, ""); split($0, a, ":"); if (a[1] != "lo") {print a[1]; exit}}' /proc/net/dev 2>/dev/null)"
    fi
    _sysinfo_net_iface="$iface"
}

_sysinfo_linux_net() {
    [[ -r /proc/net/dev && -n "$_sysinfo_net_iface" ]] || return 0
    # "  eth0: 123 ..." -- the counter may be glued to the colon, so split on it.
    local rx tx
    read -r rx tx < <(awk -v iface="$_sysinfo_net_iface" 'NR>2 {
        line = $0; sub(/^[[:space:]]+/, "", line)
        n = index(line, ":"); if (substr(line, 1, n - 1) != iface) next
        split(substr(line, n + 1), f, " "); print f[1], f[9]; exit
    }' /proc/net/dev 2>/dev/null)
    _sysinfo_network_down="$(_sysinfo_net_bytes "${rx:-}")"
    _sysinfo_network_up="$(_sysinfo_net_bytes "${tx:-}")"
}

# /proc/stat "cpu" line -> "user sys idle total" jiffies.
_sysinfo_linux_cpu_sample() {
    awk '/^cpu / {print $2 + $3, $4 + $7 + $8, $5 + $6, $2 + $3 + $4 + $5 + $6 + $7 + $8 + $9; exit}' /proc/stat 2>/dev/null
}

_sysinfo_linux_cpu() {
    [[ -r /proc/stat ]] || return 0
    # /proc/stat counts since boot; sample twice to get *current* usage.
    local u1 s1 i1 t1 u2 s2 i2 t2
    read -r u1 s1 i1 t1 < <(_sysinfo_linux_cpu_sample)
    sleep 0.25 2>/dev/null || sleep 1
    read -r u2 s2 i2 t2 < <(_sysinfo_linux_cpu_sample)
    [[ "${t1:-}" =~ ^[0-9]+$ && "${t2:-}" =~ ^[0-9]+$ ]] || return 0

    local dt=$((t2 - t1))
    if [[ "$dt" -le 0 ]]; then
        # No ticks elapsed (very coarse clock): fall back to the since-boot average.
        u1=0 s1=0 i1=0 dt="$t2"
    fi
    [[ "$dt" -gt 0 ]] || return 0
    _sysinfo_cpu_used_user=$((100 * (u2 - u1) / dt))
    _sysinfo_cpu_used_sys=$((100 * (s2 - s1) / dt))
    _sysinfo_cpu_used_idle=$((100 * (i2 - i1) / dt))
}

_sysinfo_linux_uptime() {
    local up="" secs="" load=""
    # Prefer procps `uptime -p` (keeps its wording); busybox has no -p.
    if _sysinfo_has_cmd uptime; then
        up="$(uptime -p 2>/dev/null || true)"
        [[ "$up" == up\ * ]] || up=""
    fi
    if [[ -z "$up" && -r /proc/uptime ]]; then
        secs="$(awk '{print int($1); exit}' /proc/uptime 2>/dev/null)"
        up="$(_sysinfo_fmt_duration "$secs")"
    fi
    _sysinfo_uptime_time="${up:-N/A}"

    if [[ -r /proc/loadavg ]]; then
        load="$(_sysinfo_norm_load < /proc/loadavg)"
    elif _sysinfo_has_cmd uptime; then
        load="$(uptime 2>/dev/null | sed -n 's/.*load averages*: *//p' | _sysinfo_norm_load)"
    fi
    _sysinfo_uptime_load="${load:-N/A}"
}

# Terminal UI helpers (tput/terminfo-backed).
_sysinfo_is_tty() {
    [[ -t 1 ]]
}

_sysinfo_tput() {
    # Best-effort: emit nothing if terminfo/capability isn't available.
    _sysinfo_has_cmd tput || return 1
    [[ "${TERM:-}" != "dumb" ]] || return 1
    tput "$@" 2>/dev/null || return 1
}

_sysinfo_supports_utf8() {
    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    [[ "$loc" =~ [Uu][Tt][Ff]-?8 ]]
}

# Style variables set by _sysinfo_style_init().
_SYSINFO_SGR_RESET=""
_SYSINFO_SGR_TITLE=""
_SYSINFO_SGR_LABEL=""
_SYSINFO_SGR_VALUE=""
_SYSINFO_SGR_BORDER=""
_SYSINFO_SGR_SUBLABEL=""
_SYSINFO_SGR_USED=""
_SYSINFO_SGR_FREE=""
_SYSINFO_SGR_MUTED=""
_SYSINFO_SGR_ROW_BG1=""
_SYSINFO_SGR_ROW_BG2=""

_sysinfo_tput_colors() {
    local c
    c="$(_sysinfo_tput colors || echo 0)"
    [[ "$c" =~ ^[0-9]+$ ]] || c=0
    echo "$c"
}

_sysinfo_style_init() {
    local use_colour="${1:-1}"

    _SYSINFO_SGR_RESET=""
    _SYSINFO_SGR_TITLE=""
    _SYSINFO_SGR_LABEL=""
    _SYSINFO_SGR_VALUE=""
    _SYSINFO_SGR_BORDER=""
    _SYSINFO_SGR_SUBLABEL=""
    _SYSINFO_SGR_USED=""
    _SYSINFO_SGR_FREE=""
    _SYSINFO_SGR_MUTED=""
    _SYSINFO_SGR_ROW_BG1=""
    _SYSINFO_SGR_ROW_BG2=""

    [[ "$use_colour" == "1" ]] || return 0
    _sysinfo_is_tty || return 0

    local reset bold dim colors
    reset="$(_sysinfo_tput sgr0 || true)"
    bold="$(_sysinfo_tput bold || true)"
    dim="$(_sysinfo_tput dim || true)"
    colors="$(_sysinfo_tput_colors)"

    _SYSINFO_SGR_RESET="$reset"
    if [[ "$colors" -ge 256 ]]; then
        _SYSINFO_SGR_TITLE="${bold}$(_sysinfo_tput setaf 231 || true)$(_sysinfo_tput setab 24 || true)"
        _SYSINFO_SGR_LABEL="${bold}$(_sysinfo_tput setaf 220 || true)"
        _SYSINFO_SGR_VALUE="$(_sysinfo_tput setaf 81 || true)"
        _SYSINFO_SGR_SUBLABEL="${dim}$(_sysinfo_tput setaf 250 || true)"
        _SYSINFO_SGR_USED="$(_sysinfo_tput setaf 209 || true)"
        _SYSINFO_SGR_FREE="$(_sysinfo_tput setaf 114 || true)"
        _SYSINFO_SGR_MUTED="${dim}$(_sysinfo_tput setaf 245 || true)"
        _SYSINFO_SGR_BORDER="${dim}$(_sysinfo_tput setaf 33 || true)"
        _SYSINFO_SGR_ROW_BG1="$(_sysinfo_tput setab 236 || true)"
        _SYSINFO_SGR_ROW_BG2="$(_sysinfo_tput setab 235 || true)"
    else
        local smso
        smso="$(_sysinfo_tput smso || true)"
        _SYSINFO_SGR_TITLE="${bold}${smso}$(_sysinfo_tput setaf 6 || true)"
        _SYSINFO_SGR_LABEL="${bold}$(_sysinfo_tput setaf 3 || true)"
        _SYSINFO_SGR_VALUE="$(_sysinfo_tput setaf 6 || true)"
        _SYSINFO_SGR_SUBLABEL="${dim}$(_sysinfo_tput setaf 7 || true)"
        _SYSINFO_SGR_USED="$(_sysinfo_tput setaf 3 || true)"
        _SYSINFO_SGR_FREE="$(_sysinfo_tput setaf 2 || true)"
        _SYSINFO_SGR_MUTED="${dim}$(_sysinfo_tput setaf 7 || true)"
        _SYSINFO_SGR_BORDER="${dim}$(_sysinfo_tput setaf 4 || true)"
        _SYSINFO_SGR_ROW_BG1="$smso"
        _SYSINFO_SGR_ROW_BG2=""
    fi
}

# Function to add colors and format the text output
_sysinfo_term_cols() {
    local cols=""
    if [[ -n "${COLUMNS:-}" && "${COLUMNS:-}" =~ ^[0-9]+$ && "${COLUMNS:-}" -gt 0 ]]; then
        cols="$COLUMNS"
    elif [[ -t 1 ]] && _sysinfo_has_cmd tput; then
        cols="$(tput cols 2>/dev/null || echo 80)"
    else
        cols="80"
    fi
    [[ "$cols" =~ ^[0-9]+$ ]] || cols="80"
    echo "$cols"
}

_sysinfo_visible_len() {
    # Length excluding common terminal escape sequences (CSI/OSC/charset selects).
    #
    # Notes:
    # - `tput sgr0` commonly includes `ESC(B` (G0 charset select) in addition to SGR.
    # - We strip OSC sequences so hyperlinks/window-title updates don't affect padding.
    printf '%s' "$1" | awk '
      {
        s=$0
        # CSI: ESC [ ... final-byte
        # Use octal ranges (space-/ and @-~) to avoid `/` parsing issues on BSD awk.
        gsub(/\033\[[0-9;?]*[\040-\057]*[\100-\176]/,"",s)
        # OSC: ESC ] ... BEL
        gsub(/\033\][^\007]*\007/,"",s)
        # OSC: ESC ] ... ESC \
        gsub(/\033\][^\033]*\033\\/,"",s)
        # Charset/G0-G3 selects: ESC ( X or ESC ) X
        gsub(/\033[\(\)][0-9A-Za-z]/,"",s)
        print length(s)
      }'
}

_sysinfo_fmt_uptime_short() {
    local s="$1"
    s="${s#up }"
    if [[ "$s" =~ ^([0-9]+)[[:space:]]+days?,[[:space:]]*([0-9]+):([0-9]{2})$ ]]; then
        printf '%sd %sh%sm' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
        return 0
    fi
    if [[ "$s" =~ ^([0-9]+):([0-9]{2})$ ]]; then
        printf '%sh%sm' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
        return 0
    fi

    # Best-effort normalization for strings like:
    # - "11 hours, 35 minutes"
    # - "1 day, 2 hours, 3 minutes"
    printf '%s' "$s" | sed -E \
        -e 's/,//g' \
        -e 's/[[:space:]]+years?/y/g' \
        -e 's/[[:space:]]+weeks?/w/g' \
        -e 's/[[:space:]]+days?/d/g' \
        -e 's/[[:space:]]+hours?/h/g' \
        -e 's/[[:space:]]+minutes?/m/g' \
        -e 's/[[:space:]]+secs?/s/g' \
        -e 's/[[:space:]]+/ /g' \
        -e 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

_sysinfo_repeat() {
    local ch="$1" count="$2"
    local i
    for ((i = 0; i < count; i++)); do
        printf '%s' "$ch"
    done
}

_sysinfo_spaces() {
    local count="$1"
    [[ "$count" -gt 0 ]] || count=0
    printf '%*s' "$count" ""
}

_sysinfo_pad_right() {
    local text="$1" width="$2"
    local vis pad
    vis="$(_sysinfo_visible_len "$text")"
    pad=$((width - vis))
    [[ "$pad" -gt 0 ]] || pad=0
    printf '%s%*s' "$text" "$pad" ""
}

_sysinfo_box_row_bg() {
    local idx="$1"
    if (( idx % 2 == 0 )); then
        printf '%s' "${_SYSINFO_SGR_ROW_BG1}"
    else
        printf '%s' "${_SYSINFO_SGR_ROW_BG2}"
    fi
}

_sysinfo_box_span() {
    local row_bg="$1" sgr="$2" text="$3"
    printf '%s%s%s%s' "${_SYSINFO_SGR_RESET}" "${row_bg}" "${sgr}" "${text}"
}

_sysinfo_box_fmt_pair() {
    local row_bg="$1" k="$2" v="$3"
    [[ -n "$v" ]] || v="N/A"
    printf '%s%s%s' \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "${k} ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "$v")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "")"
}

_sysinfo_box_fmt_used_total_free() {
    local row_bg="$1" used="$2" total="$3" free="$4"
    [[ -n "$used" ]] || used="N/A"
    [[ -n "$total" ]] || total="N/A"
    [[ -n "$free" ]] || free="N/A"
    printf '%s%s%s%s%s%s%s%s%s' \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "Used ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_USED" "$used")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "Total ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "$total")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "Free ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_FREE" "$free")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "")"
}

_sysinfo_box_fmt_cpu() {
    local row_bg="$1" u="$2" s="$3" i="$4"
    [[ -n "$u" ]] || u="N/A"
    [[ -n "$s" ]] || s="N/A"
    [[ -n "$i" ]] || i="N/A"
    printf '%s%s%s%s%s%s%s%s%s' \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "User ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_USED" "${u}%")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "Sys ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_USED" "${s}%")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "Idle ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_FREE" "${i}%")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "")"
}

_sysinfo_box_fmt_net() {
    local row_bg="$1" rx="$2" tx="$3"
    [[ -n "$rx" ]] || rx="N/A"
    [[ -n "$tx" ]] || tx="N/A"
    printf '%s%s%s%s%s%s' \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "RX ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_FREE" "$rx")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "TX ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_USED" "$tx")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "")"
}

_sysinfo_box_fmt_load() {
    local row_bg="$1" raw="$2"
    local a b c
    a="$(printf '%s' "$raw" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}')"
    b="$(printf '%s' "$raw" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}')"
    c="$(printf '%s' "$raw" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3}')"
    [[ -n "$a" ]] || a="N/A"
    [[ -n "$b" ]] || b="N/A"
    [[ -n "$c" ]] || c="N/A"
    printf '%s%s%s%s%s%s%s%s%s' \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "1m ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "$a")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "5m ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "$b")" \
        "$(_sysinfo_box_span "$row_bg" "" "  ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_SUBLABEL" "15m ")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "$c")" \
        "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "")"
}

_sysinfo_box_print_row() {
    local row_bg="$1" label="$2" value="$3" label_w="$4" value_w="$5" v_border="$6"
    local label_pad

    label_pad=$((label_w - ${#label}))
    [[ "$label_pad" -ge 0 ]] || label_pad=0

    local vis pad
    vis="$(_sysinfo_visible_len "$value")"
    pad=$((value_w - vis))
    [[ "$pad" -ge 0 ]] || pad=0

    # Left border (no row background).
    printf '%s' "${_SYSINFO_SGR_BORDER}${v_border}${_SYSINFO_SGR_RESET}"

    # Interior (with row background).
    printf '%s' "$(_sysinfo_box_span "$row_bg" "" " ")"
    printf '%s' "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_LABEL" "$label")"
    printf '%s' "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "$(_sysinfo_spaces "$label_pad")")"
    printf '%s' "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_MUTED" " : ")"

    # Value + explicit padding (do not rely on inherited background state).
    printf '%s' "$value"
    printf '%s%*s' "$(_sysinfo_box_span "$row_bg" "$_SYSINFO_SGR_VALUE" "")" "$pad" ""

    printf '%s' "$(_sysinfo_box_span "$row_bg" "" " ")"

    # Right border, then reset so shell prompt isn't affected.
    printf '%s\n' "${_SYSINFO_SGR_RESET}${_SYSINFO_SGR_BORDER}${v_border}${_SYSINFO_SGR_RESET}"
}

_sysinfo_pretty_used_total_free() {
    local used="$1" total="$2" free="$3"
    [[ -n "$used" ]] || used="N/A"
    [[ -n "$total" ]] || total="N/A"
    [[ -n "$free" ]] || free="N/A"
    printf '%sUsed%s %s%s%s  %sTotal%s %s%s%s  %sFree%s %s%s%s' \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_USED}" "$used" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_VALUE}" "$total" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_FREE}" "$free" "${_SYSINFO_SGR_RESET}"
}

_sysinfo_pretty_cpu() {
    local u="$1" s="$2" i="$3"
    [[ -n "$u" ]] || u="N/A"
    [[ -n "$s" ]] || s="N/A"
    [[ -n "$i" ]] || i="N/A"
    printf '%sUser%s %s%s%%%s  %sSys%s %s%s%%%s  %sIdle%s %s%s%%%s' \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_USED}" "$u" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_USED}" "$s" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_FREE}" "$i" "${_SYSINFO_SGR_RESET}"
}

_sysinfo_pretty_load() {
    local raw="$1"
    local a b c
    a="$(printf '%s' "$raw" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$1); print $1}')"
    b="$(printf '%s' "$raw" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2}')"
    c="$(printf '%s' "$raw" | awk -F',' '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$3); print $3}')"
    [[ -n "$a" ]] || a="N/A"
    [[ -n "$b" ]] || b="N/A"
    [[ -n "$c" ]] || c="N/A"
    printf '%s1m%s %s%s%s  %s5m%s %s%s%s  %s15m%s %s%s%s' \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_VALUE}" "$a" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_VALUE}" "$b" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_VALUE}" "$c" "${_SYSINFO_SGR_RESET}"
}

_sysinfo_pretty_net() {
    local rx="$1" tx="$2"
    [[ -n "$rx" ]] || rx="N/A"
    [[ -n "$tx" ]] || tx="N/A"
    printf '%sRX%s %s%s%s  %sTX%s %s%s%s' \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_FREE}" "$rx" "${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_SUBLABEL}" "${_SYSINFO_SGR_RESET}" "${_SYSINFO_SGR_USED}" "$tx" "${_SYSINFO_SGR_RESET}"
}

_sysinfo_wrap() {
    local text="$1" width="$2"
    if _sysinfo_has_cmd fold; then
        # fold handles long words by hard-splitting; good enough for terminal UI.
        # Always include a trailing newline so downstream `read` loops run.
        printf '%s\n' "$text" | fold -s -w "$width"
    else
        # Fallback: no wrapping.
        printf '%s\n' "$text"
    fi
}

_sysinfo_render_box() {
    local use_colour="${1:-1}"
    local cols width inner content_w label_w value_w
    cols="$(_sysinfo_term_cols)"

    _sysinfo_style_init "$use_colour"

    _sysinfo_is_tty || { _sysinfo_render_segments "$use_colour"; return 0; }

    if [[ "$cols" -lt 60 ]]; then
        _sysinfo_render_segments "$use_colour"
        return 0
    fi

    width="$cols"
    [[ "$width" -gt 100 ]] && width=100
    [[ "$width" -ge 40 ]] || { _sysinfo_render_segments "$use_colour"; return 0; }

    inner=$((width - 2))
    content_w=$((width - 4))

    local tl tr bl br h v
    if _sysinfo_supports_utf8; then
        tl="┌" tr="┐" bl="└" br="┘" h="─" v="│"
    else
        tl="+" tr="+" bl="+" br="+" h="-" v="|"
    fi

    # Fixed label width; keep the layout stable.
    label_w=6

    value_w=$((content_w - label_w - 3))
    [[ "$value_w" -ge 10 ]] || { _sysinfo_render_segments "$use_colour"; return 0; }

    local title_text=" System Info "
    local title_len="${#title_text}"
    local rem=$((inner - title_len))
    local left=$((rem / 2))
    local right=$((rem - left))

    printf '%s%s%s%s%s\n' \
        "${_SYSINFO_SGR_BORDER}${tl}${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_BORDER}$(_sysinfo_repeat "$h" "$left")${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_TITLE}${title_text}${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_BORDER}$(_sysinfo_repeat "$h" "$right")${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_BORDER}${tr}${_SYSINFO_SGR_RESET}"

    local row=0 content

    local row_bg

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_pair "$row_bg" "Name" "${_sysinfo_os_name:-N/A}")$(_sysinfo_box_span "$row_bg" "" "  ")$(_sysinfo_box_fmt_pair "$row_bg" "Ver" "${_sysinfo_os_ver:-N/A}")"
    _sysinfo_box_print_row "$row_bg" "OS" "$content" "$label_w" "$value_w" "$v"
    row=$((row + 1))

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_used_total_free "$row_bg" "${_sysinfo_startup_used:-N/A}" "${_sysinfo_startup_size:-N/A}" "${_sysinfo_startup_free:-N/A}")"
    _sysinfo_box_print_row "$row_bg" "Disk" "$content" "$label_w" "$value_w" "$v"
    row=$((row + 1))

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_pair "$row_bg" "Up" "$(_sysinfo_fmt_uptime_short "${_sysinfo_uptime_time:-N/A}")")"
    _sysinfo_box_print_row "$row_bg" "Uptime" "$content" "$label_w" "$value_w" "$v"
    row=$((row + 1))

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_load "$row_bg" "${_sysinfo_uptime_load:-N/A}")"
    _sysinfo_box_print_row "$row_bg" "Load" "$content" "$label_w" "$value_w" "$v"
    row=$((row + 1))

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_cpu "$row_bg" "${_sysinfo_cpu_used_user:-N/A}" "${_sysinfo_cpu_used_sys:-N/A}" "${_sysinfo_cpu_used_idle:-N/A}")"
    _sysinfo_box_print_row "$row_bg" "CPU" "$content" "$label_w" "$value_w" "$v"
    row=$((row + 1))

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_used_total_free "$row_bg" "${_sysinfo_ram_used:-N/A}" "${_sysinfo_ram_total:-N/A}" "${_sysinfo_ram_free:-N/A}")"
    _sysinfo_box_print_row "$row_bg" "RAM" "$content" "$label_w" "$value_w" "$v"
    row=$((row + 1))

    row_bg="$(_sysinfo_box_row_bg "$row")"
    content="$(_sysinfo_box_fmt_net "$row_bg" "${_sysinfo_network_down:-N/A}" "${_sysinfo_network_up:-N/A}")"
    _sysinfo_box_print_row "$row_bg" "Net" "$content" "$label_w" "$value_w" "$v"

    printf '%s%s%s\n' \
        "${_SYSINFO_SGR_BORDER}${bl}${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_BORDER}$(_sysinfo_repeat "$h" "$inner")${_SYSINFO_SGR_RESET}" \
        "${_SYSINFO_SGR_BORDER}${br}${_SYSINFO_SGR_RESET}"
}

_sysinfo_render_segments() {
    local use_colour="${1:-1}"
    local cols sep sep_len
    cols="$(_sysinfo_term_cols)"
    sep="  "
    sep_len=2

    _sysinfo_style_init "$use_colour"
    local c_label="$_SYSINFO_SGR_LABEL" c_value="$_SYSINFO_SGR_VALUE" c_reset="$_SYSINFO_SGR_RESET"

    local os disk uptime load cpu ram net
    os="${_sysinfo_os_name} ${_sysinfo_os_ver}"
    disk="${_sysinfo_startup_name} $(_sysinfo_pretty_used_total_free "$_sysinfo_startup_used" "$_sysinfo_startup_size" "$_sysinfo_startup_free")"
    uptime="$(_sysinfo_fmt_uptime_short "$_sysinfo_uptime_time")"
    load="$(_sysinfo_pretty_load "$_sysinfo_uptime_load")"
    cpu="$(_sysinfo_pretty_cpu "$_sysinfo_cpu_used_user" "$_sysinfo_cpu_used_sys" "$_sysinfo_cpu_used_idle")"
    ram="$(_sysinfo_pretty_used_total_free "$_sysinfo_ram_used" "$_sysinfo_ram_total" "$_sysinfo_ram_free")"
    net="$(_sysinfo_pretty_net "$_sysinfo_network_down" "$_sysinfo_network_up")"

    local segments=(
        "${c_label}OS${c_reset}: ${c_value}${os}${c_reset}"
        "${c_label}Disk${c_reset}: ${c_value}${disk}${c_reset}"
        "${c_label}Uptime${c_reset}: ${c_value}${uptime}${c_reset}"
        "${c_label}Load${c_reset}: ${c_value}${load}${c_reset}"
        "${c_label}CPU${c_reset}: ${c_value}${cpu}${c_reset}"
        "${c_label}RAM${c_reset}: ${c_value}${ram}${c_reset}"
        "${c_label}Net${c_reset}: ${c_value}${net}${c_reset}"
    )

    if [[ "$cols" -lt 60 ]]; then
        local seg
        for seg in "${segments[@]}"; do
            printf '%s\n' "$seg"
        done
        return 0
    fi

    local line="" line_len=0 seg seg_len
    for seg in "${segments[@]}"; do
        seg_len="$(_sysinfo_visible_len "$seg")"
        if [[ "$line_len" -eq 0 ]]; then
            line="$seg"
            line_len="$seg_len"
        elif [[ $((line_len + sep_len + seg_len)) -le "$cols" ]]; then
            line+="$sep$seg"
            line_len=$((line_len + sep_len + seg_len))
        else
            printf '%s\n' "$line"
            line="$seg"
            line_len="$seg_len"
        fi
    done
    [[ -n "$line" ]] && printf '%s\n' "$line"
}

_sysinfo_render_table() {
    local use_colour="${1:-1}"
    _sysinfo_style_init "$use_colour"
    local c_label="$_SYSINFO_SGR_LABEL" c_value="$_SYSINFO_SGR_VALUE" c_reset="$_SYSINFO_SGR_RESET"

    local os disk uptime load cpu ram net
    os="${_sysinfo_os_name} ${_sysinfo_os_ver}"
    disk="${_sysinfo_startup_name} $(_sysinfo_pretty_used_total_free "$_sysinfo_startup_used" "$_sysinfo_startup_size" "$_sysinfo_startup_free")"
    uptime="$(_sysinfo_fmt_uptime_short "$_sysinfo_uptime_time")"
    load="$(_sysinfo_pretty_load "$_sysinfo_uptime_load")"
    cpu="$(_sysinfo_pretty_cpu "$_sysinfo_cpu_used_user" "$_sysinfo_cpu_used_sys" "$_sysinfo_cpu_used_idle")"
    ram="$(_sysinfo_pretty_used_total_free "$_sysinfo_ram_used" "$_sysinfo_ram_total" "$_sysinfo_ram_free")"
    net="$(_sysinfo_pretty_net "$_sysinfo_network_down" "$_sysinfo_network_up")"

    printf '%s\n' \
        "${c_label}OS${c_reset} | ${c_label}Disk${c_reset} | ${c_label}Uptime${c_reset} | ${c_label}Load${c_reset} | ${c_label}CPU${c_reset} | ${c_label}RAM${c_reset} | ${c_label}Net${c_reset}"
    printf '%s\n' \
        "${c_value}${os}${c_reset} | ${c_value}${disk}${c_reset} | ${c_value}${uptime}${c_reset} | ${c_value}${load}${c_reset} | ${c_value}${cpu}${c_reset} | ${c_value}${ram}${c_reset} | ${c_value}${net}${c_reset}"
}

_sysinfo_print_terminal() {
    local use_colour="${1:-1}"
    local layout="${2:-auto}"
    local cols
    cols="$(_sysinfo_term_cols)"

    case "$layout" in
        box)
            _sysinfo_render_box "$use_colour"
            ;;
        table)
            _sysinfo_render_table "$use_colour"
            ;;
        stacked|segments)
            _sysinfo_render_segments "$use_colour"
            ;;
        auto|*)
            # Pretty box for interactive sessions; simple wrapped output elsewhere.
            if _sysinfo_is_tty && _sysinfo_has_cmd tput && [[ "${TERM:-}" != "dumb" ]] && [[ "$cols" -ge 60 ]]; then
                _sysinfo_render_box "$use_colour"
            else
                _sysinfo_render_segments "$use_colour"
            fi
            ;;
    esac
}

_SYSINFO_KV_KEYS=(os os_version boot_volume volume_size volume_used volume_free uptime load_avg cpu_user cpu_sys cpu_idle ram_used ram_free ram_total net_rx net_tx)

_sysinfo_print_kv() {
    # Machine-friendly output: one key=value per line.
    local key value
    for key in "${_SYSINFO_KV_KEYS[@]}"; do
        case "$key" in
            os) value="$_sysinfo_os_name" ;;
            os_version) value="$_sysinfo_os_ver" ;;
            boot_volume) value="$_sysinfo_startup_name" ;;
            volume_size) value="$_sysinfo_startup_size" ;;
            volume_used) value="$_sysinfo_startup_used" ;;
            volume_free) value="$_sysinfo_startup_free" ;;
            uptime) value="$_sysinfo_uptime_time" ;;
            load_avg) value="$_sysinfo_uptime_load" ;;
            cpu_user) value="$_sysinfo_cpu_used_user" ;;
            cpu_sys) value="$_sysinfo_cpu_used_sys" ;;
            cpu_idle) value="$_sysinfo_cpu_used_idle" ;;
            ram_used) value="$_sysinfo_ram_used" ;;
            ram_free) value="$_sysinfo_ram_free" ;;
            ram_total) value="$_sysinfo_ram_total" ;;
            net_rx) value="$_sysinfo_network_down" ;;
            net_tx) value="$_sysinfo_network_up" ;;
            *) value="N/A" ;;
        esac
        printf '%s=%s\n' "$key" "${value:-N/A}"
    done
}

_sysinfo_usage() {
    cat <<'USAGE'
Usage: sysinfo [--help] [--plain|--no-color] [--kv] [--box|--table|--stacked]

Human output is the default.

Options:
    -h, --help        Show this help and exit.
    --box             Pretty boxed output (uses terminfo via `tput` when available).
    --table, --wide   Force a single-row table (best on wide terminals).
    --stacked, --compact
                     Force a wrapped multi-line layout (best on narrow terminals).
    --plain, --no-color
                                     Disable ANSI color.
    --kv              Machine-readable key=value output (one per line).

Environment:
    SYSINFO_LAYOUT    One of: auto, box, table, stacked. (Default: auto)

Exit codes:
    0 success
    1 runtime error
    2 usage/unknown option
USAGE
}

_sysinfo_main() {
    local output_mode="${1:-human}"
    local use_colour="${2:-1}"
    local layout="${3:-auto}"
    _sysinfo_reset
    _sysinfo_find_os || return 1

    if [[ "$_sysinfo_which_os" -eq 1 ]]; then
        _sysinfo_mac_disk
        _sysinfo_mac_net
        _sysinfo_mac_cpu
        _sysinfo_mac_uptime
        _sysinfo_mac_ram
    else
        _sysinfo_linux_detect_iface
        _sysinfo_linux_disk
        _sysinfo_linux_net
        _sysinfo_linux_cpu
        _sysinfo_linux_uptime
        _sysinfo_linux_ram
    fi

    if [[ "$output_mode" == "kv" ]]; then
        _sysinfo_print_kv
    else
        _sysinfo_print_terminal "$use_colour" "$layout"
    fi
}

sysinfo() {
    local output_mode="human"
    local colour_mode="auto"
    local layout="${SYSINFO_LAYOUT:-auto}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                _sysinfo_usage
                return 0
                ;;
            --kv|--key-value)
                output_mode="kv"
                ;;
            --table|--wide)
                layout="table"
                ;;
            --stacked|--compact)
                layout="stacked"
                ;;
            --box)
                layout="box"
                ;;
            --plain|--no-color)
                colour_mode="off"
                ;;
            --color)
                colour_mode="on"
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "sysinfo: unknown option: $1" >&2
                _sysinfo_usage >&2
                return 2
                ;;
        esac
        shift
    done

    local use_colour=1
    case "$colour_mode" in
        off) use_colour=0 ;;
        on)  use_colour=1 ;;
        auto)
            if [[ -t 1 ]]; then
                use_colour=1
            else
                use_colour=0
            fi
            ;;
    esac

    _sysinfo_main "$output_mode" "$use_colour" "$layout"
}

#------------------------------------------------------------------------------
# Bash completion (registered only for interactive shells)
#------------------------------------------------------------------------------

_sysinfo_completion() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [[ "$cur" == -* ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "-h --help --kv --key-value --box --table --wide --stacked --compact --plain --no-color --color --" -- "$cur") )
        return 0
    fi

    COMPREPLY=()
    return 0
}

if [[ $- == *i* ]]; then
    if command -v complete >/dev/null 2>&1; then
        complete -F _sysinfo_completion sysinfo 2>/dev/null || true
    fi
fi

# Run only when executed directly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    sysinfo "$@"
fi
