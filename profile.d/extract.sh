#------------------------------------------------------------------------------
# Archive extraction helper
#------------------------------------------------------------------------------

# shellcheck shell=bash

# If sourced standalone (without 10-common.sh), provide a tiny fallback.
if ! declare -F has_cmd >/dev/null 2>&1; then
    has_cmd() { command -v "$1" >/dev/null 2>&1; }
fi

_extract_usage() {
    cat <<'USAGE'
Usage: extract [--help] [-v|--verbose] [-l|--list] [-f|--force] <archive> [dest]

Options:
  -h, --help     Show this help and exit.
  -v, --verbose  Print the command used and enable verbose mode for tools that support it.
  -l, --list     List archive contents (when supported).
  -f, --force    Allow potentially unsafe paths in archives and allow overwriting.

Exit codes:
  0 success
  1 runtime error
  2 usage/unknown option
USAGE
}

# Safety (skipped with --force): refuse obvious path traversal, and refuse to
# extract over files that already exist in <dest>. bsdtar -k, unzip -n and
# 7z -aos skip existing files silently with exit 0, so check up front to get a
# message and exit 1 on every platform. Existing directories are fine.
# Usage: _extract_check_paths <archive> <dest> <list-cmd...>   (list-cmd prints one path per line)
_extract_check_paths() {
    local file="$1" dest="$2"
    shift 2
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" == /* || "$line" == ".." || "$line" == ../* || "$line" == *"/../"* || "$line" == */.. ]]; then
            echo "extract: potential unsafe path detected: $line (use --force to override)" >&2
            return 1
        fi
        if [[ -L "$dest/$line" ]] || [[ -e "$dest/$line" && ! -d "$dest/$line" ]]; then
            echo "extract: '$dest/$line' already exists (use --force to overwrite)" >&2
            return 1
        fi
    done < <("$@" "$file")
}

# `7z l -ba` prefixes each path with date/size columns; print bare paths instead.
_extract_7z_paths() {
    7z l -slt -ba "$1" 2>/dev/null | sed -n 's/^Path = //p'
}

# Decompress a single-file format (.gz, .bz2, ...) without clobbering.
# Usage: _extract_single <force:true|false> <out> <cmd...>   (cmd writes to stdout)
_extract_single() {
    local force="$1" out="$2"
    shift 2
    if [[ -e "$out" ]] && ! $force; then
        echo "extract: '$out' already exists (use --force to overwrite)" >&2
        return 1
    fi
    "$@" > "$out"
}

extract() {
    local verbose=false list=false force=false archive="" dest=""
    local positional=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    _extract_usage; return 0 ;;
            -v|--verbose) verbose=true ;;
            -l|--list)    list=true ;;
            -f|--force)   force=true ;;
            --) shift; positional+=("$@"); break ;;
            -*) echo "extract: unknown option: $1" >&2; _extract_usage >&2; return 2 ;;
            *)  positional+=("$1") ;;
        esac
        shift
    done
    if [[ ${#positional[@]} -gt 2 ]]; then
        echo "extract: too many arguments (expected <archive> [dest])" >&2
        return 2
    fi
    [[ ${#positional[@]} -ge 1 ]] && archive="${positional[0]}"
    [[ ${#positional[@]} -ge 2 ]] && dest="${positional[1]}"
    if [[ -z "$archive" ]]; then
        _extract_usage >&2
        return 2
    fi

    if [[ ! -f "$archive" || ! -r "$archive" ]]; then
        echo "extract: archive '$archive' is not readable." >&2
        return 1
    fi

    local archive_name base lc
    archive_name="$(basename "$archive")"
    # Lowercased name for format matching, so patterns below are lowercase only.
    lc="$(LC_ALL=C printf '%s' "$archive_name" | tr '[:upper:]' '[:lower:]')"

    if $list; then
        case "$lc" in
            *.tar.bz2|*.tbz2)   tar tjf "$archive" ;;
            *.tar.gz|*.tgz)     tar tzf "$archive" ;;
            *.tar.xz|*.txz)     tar tJf "$archive" ;;
            *.tar.z)            tar tZf "$archive" ;;
            *.tar)              tar tf "$archive" ;;
            *.zip)              unzip -l "$archive" ;;
            *.rar)              unrar l "$archive" ;;
            *.7z)               7z l "$archive" ;;
            *.gz|*.bz2|*.xz|*.lzma|*.z)
                echo "Listing not supported for single-file compression; will output filename only."
                echo "${archive_name%.*}"
                ;;
            *)
                echo "extract: cannot list '$archive' (unknown format)" >&2
                return 1
                ;;
        esac
        return $?
    fi

    # Guess destination directory if not provided.
    case "$lc" in
        *.tar.*) base="${archive_name%.[Tt][Aa][Rr].*}" ;;
        *)       base="${archive_name%.*}" ;;
    esac
    dest="${dest:-$base}"

    # Reject unsupported formats before creating anything on disk.
    case "$lc" in
        *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.z|*.tar|*.zip|*.rar|*.7z|*.gz|*.bz2|*.xz|*.lzma|*.z) ;;
        *)
            echo "extract: cannot extract '$archive' (unsupported format)" >&2
            return 1
            ;;
    esac

    [[ -d "$dest" ]] || mkdir -p "$dest" || return 1

    # Don't overwrite existing files unless --force was requested.
    # GNU tar supports: --keep-old-files
    # bsdtar (macOS /usr/bin/tar) supports: -k
    local tar_opts=()
    if ! $force; then
        if tar --help 2>/dev/null | grep -q -- '--keep-old-files'; then
            tar_opts+=("--keep-old-files")
        else
            tar_opts+=(-k)
        fi
    fi
    $verbose && tar_opts+=(-v)

    local cmd_desc=""
    case "$lc" in
        *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.z|*.tar)
            local tar_mode
            case "$lc" in
                *.tar.bz2|*.tbz2) tar_mode=j ;;
                *.tar.gz|*.tgz)   tar_mode=z ;;
                *.tar.xz|*.txz)   tar_mode=J ;;
                *.tar.z)          tar_mode=Z ;;
                *)                tar_mode="" ;;
            esac
            if ! $force; then
                _extract_check_paths "$archive" "$dest" tar "t${tar_mode}f" || return 1
            fi
            cmd_desc="tar x${tar_mode}f"
            # ${arr[@]+...}: an empty array is "unbound" under set -u in Bash < 4.4.
            tar "x${tar_mode}f" "$archive" -C "$dest" ${tar_opts[@]+"${tar_opts[@]}"}
            ;;
        *.zip)
            if ! has_cmd unzip; then
                echo "unzip is required to extract zip archives." >&2
                return 1
            fi
            if ! $force; then
                _extract_check_paths "$archive" "$dest" unzip -Z1 || return 1
            fi
            cmd_desc="unzip"
            # -o overwrite / -n never overwrite (without either, unzip prompts).
            # Note: unzip's -v means "list verbosely", so verbose maps to dropping -q.
            local unzip_opts=(-n)
            $force && unzip_opts=(-o)
            $verbose || unzip_opts+=(-q)
            unzip "${unzip_opts[@]}" "$archive" -d "$dest"
            ;;
        *.rar)
            if ! has_cmd unrar; then
                echo "unrar is required to extract rar archives." >&2
                return 1
            fi
            if ! $force; then
                _extract_check_paths "$archive" "$dest" unrar lb || return 1
            fi
            cmd_desc="unrar"
            local unrar_overwrite="-o-"
            $force && unrar_overwrite="-o+"
            unrar x "$unrar_overwrite" "$archive" "$dest/"
            ;;
        *.7z)
            if ! has_cmd 7z; then
                echo "7z is required to extract 7z archives." >&2
                return 1
            fi
            if ! $force; then
                _extract_check_paths "$archive" "$dest" _extract_7z_paths || return 1
            fi
            cmd_desc="7z x"
            # -aoa overwrite all / -aos skip existing (without either, 7z prompts).
            local sz_opts=(-aos)
            $force && sz_opts=(-aoa)
            if $verbose; then
                sz_opts+=(-bb1)
            else
                sz_opts+=(-bso0 -bsp0)   # quiet like tar/unzip; errors still go to stderr
            fi
            7z x "$archive" -o"$dest" "${sz_opts[@]}"
            ;;
        *.gz)
            if ! has_cmd gunzip; then
                echo "gunzip is required to extract gz files." >&2
                return 1
            fi
            cmd_desc="gunzip"
            _extract_single "$force" "$dest/${archive_name%.*}" gunzip -c "$archive"
            ;;
        *.bz2)
            if ! has_cmd bunzip2; then
                echo "bunzip2 is required to extract bz2 files." >&2
                return 1
            fi
            cmd_desc="bunzip2"
            _extract_single "$force" "$dest/${archive_name%.*}" bunzip2 -c "$archive"
            ;;
        *.xz)
            if ! has_cmd xz; then
                echo "xz is required to extract xz files." >&2
                return 1
            fi
            cmd_desc="xz --decompress"
            _extract_single "$force" "$dest/${archive_name%.*}" xz -dc "$archive"
            ;;
        *.lzma)
            if ! has_cmd xz; then
                echo "xz (lzma format) is required to extract lzma files." >&2
                return 1
            fi
            cmd_desc="xz --format=lzma --decompress"
            _extract_single "$force" "$dest/${archive_name%.*}" xz --format=lzma -dc "$archive"
            ;;
        *.z)
            # gzip reads compress(1) .Z files too, and is far more common.
            if has_cmd uncompress; then
                cmd_desc="uncompress"
                _extract_single "$force" "$dest/${archive_name%.*}" uncompress -c "$archive"
            elif has_cmd gzip; then
                cmd_desc="gzip --decompress"
                _extract_single "$force" "$dest/${archive_name%.*}" gzip -dc "$archive"
            else
                echo "uncompress or gzip is required to extract .Z files." >&2
                return 1
            fi
            ;;
    esac || return 1   # contract: runtime failure exits 1 (not the tool's own code)

    if $verbose; then
        echo "Extracted with: $cmd_desc -> $dest"
    fi
    return 0
}

#------------------------------------------------------------------------------
# Bash completion (opt-in by context: only registered for interactive shells)
#
# Notes:
# - Compatible with macOS /bin/bash 3.2.
# - Safe to source: defines a function and (optionally) registers completion.
# - We keep the completion lightweight and conservative.
#------------------------------------------------------------------------------

_extract_completion() {
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    # Complete options.
    if [[ "$cur" == -* ]]; then
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -W "-h --help -v --verbose -l --list -f --force --" -- "$cur") )
        return 0
    fi

    # Determine whether we've already seen the archive argument.
    # extract [opts] <archive> [dest]
    local i word archive_seen=0
    for (( i=1; i<COMP_CWORD; i++ )); do
        word="${COMP_WORDS[i]}"
        case "$word" in
            --) break ;;
            -h|--help|-v|--verbose|-l|--list|-f|--force) continue ;;
            -*) continue ;; # unknown option; don't try to be clever
            *) archive_seen=1; break ;;
        esac
    done

    if [[ "$archive_seen" -eq 0 ]]; then
        # First positional arg: archive file.
        # Prefer files; allow common archive suffixes but don't over-filter.
        # shellcheck disable=SC2207
        COMPREPLY=( $(compgen -f -- "$cur") )
        return 0
    fi

    # Second positional arg: destination directory.
    # shellcheck disable=SC2207
    COMPREPLY=( $(compgen -d -- "$cur") )
    return 0
}

# Register completion only in interactive shells.
if [[ $- == *i* ]]; then
    # `complete` is a bash builtin, but guard anyway.
    if command -v complete >/dev/null 2>&1; then
        complete -F _extract_completion extract 2>/dev/null || true
    fi
fi
