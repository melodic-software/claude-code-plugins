#!/usr/bin/env bash
# Upstream docs cache, shared by the plugins that read vendor docs pages.
#
# fetch-docs.sh sources this file for --cache; the CLI below reads what it
# stored. The cache stores page bytes, validates them and returns them or
# their sections. It never decides which section is relevant: the caller
# names the sections it wants.
#
# Store layout under the cache directory. A name is the first 16 hex digits of
# the key and of the sha256, so paths stay under Windows' 260-character limit;
# the full values are in the pointer and meta.json, and a reader checks both,
# so two keys sharing a prefix read as a miss, never as each other's bytes. A
# write whose longest path would pass the limit is refused with that reason.
#   store_version          the layout version; a reader that meets another
#                          version treats the store as empty and a writer
#                          refuses to write
#   entries/<key16>-<sha16> one immutable entry: body (the raw bytes), meta.json
#                          and map.tsv. It is built in a .tmp-* directory beside
#                          it and renamed into place complete (never into an
#                          existing directory), and never modified after.
#   keys/<key16>           the key's pointer: one line, tab-separated: the current
#                          entry as <key>-<sha256>, the validated epoch, the validated UTC
#                          ISO time and, when the fetch that last confirmed the
#                          entry was told how to revalidate, a validators record:
#                          accept, request URL, ETag and Last-Modified joined by
#                          \x1f. It is switched by writing a temp file and
#                          renaming it over the old one; a reader reads it once
#                          and then only the entry it named.
#   keys/<key16>.access    last access epoch, written best-effort on every
#                          read and write
#   keys/<key16>.quarantine written when an entry replaces one whose title
#                          differs: JSON with at, from_entry, from_title,
#                          to_entry and to_title. Nothing here removes it; a
#                          reader withholds what it derived from the key.
#
# key is sha256 of the normalized URL (scheme and host lower-cased, fragment
# dropped), a newline and the format. meta.json holds store_version, key, url,
# format, sha256 (of body), bytes, content_type, title (the body's first
# heading, else the title the writer passed, else null) and retrieved (when
# these bytes were first stored). validated (when they were last confirmed
# current) and the validators live in the pointer, so confirming unchanged
# bytes rewrites only the pointer.
#
# A section starts at a heading outside fenced code and runs to the next
# heading of the same or a higher level. map.tsv has one row per section:
#   id level start end bytes sha256 heading_path
# start and end are line numbers, bytes counts the section with its child
# sections, and sha256 covers the section's own body only: the lines after its
# heading up to the next heading of any level. A renamed heading therefore
# keeps its hash, and a child change leaves the parent's hash alone.
#
# Exit codes:
#   0  done
#   1  miss: no usable entry for the key, or an unknown section id
#   2  fatal (bad arguments, jq missing, nothing stored)
#
# Env overrides:
#   DOCS_CACHE_DIR  cache directory when --cache-dir is absent (default:
#                   ${XDG_CACHE_HOME:-$HOME/.cache}/claude-docs-cache)
#   DOCS_CACHE_NOW  epoch seconds to use as the current time (the test seam)
#   DOCS_CACHE_PATH_MAX  the path-length limit for writes (default 259 on
#                   Windows, none elsewhere)

DC_STORE_VERSION=2

# dc_set_dir [dir]: set DC_DIR from the argument, else DOCS_CACHE_DIR, else the default.
dc_set_dir() {
  DC_DIR="${1:-${DOCS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/claude-docs-cache}}"
}

# dc_now: set DC_NOW (epoch) and DC_NOW_ISO (UTC ISO) from the clock or DOCS_CACHE_NOW.
dc_now() {
  if [[ "${DOCS_CACHE_NOW:-}" =~ ^[0-9]+$ ]]; then DC_NOW="$DOCS_CACHE_NOW"; else printf -v DC_NOW '%(%s)T' -1; fi
  TZ=UTC0 printf -v DC_NOW_ISO '%(%Y-%m-%dT%H:%M:%SZ)T' "$DC_NOW"
}

dc_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

# dc_key <url> <format>: print the cache key.
dc_key() {
  local url="${1%%#*}"
  [[ "$url" =~ ^([A-Za-z][A-Za-z0-9+.-]*://[^/]*)(.*)$ ]] && url="${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
  printf '%s\n%s' "$url" "$2" | dc_sha256
}

# dc_readable: the store exists at this layout version.
dc_readable() {
  local v=""
  [[ -f "$DC_DIR/store_version" ]] && read -r v <"$DC_DIR/store_version"
  [[ "$v" == "$DC_STORE_VERSION" ]]
}

# dc_writable: create the store if absent; fail on another layout version.
dc_writable() {
  local tmp
  mkdir -p "$DC_DIR/entries" "$DC_DIR/keys" 2>/dev/null || return 1
  if [[ ! -f "$DC_DIR/store_version" ]]; then
    tmp="$DC_DIR/.tmp-version-$$-$RANDOM"
    printf '%s\n' "$DC_STORE_VERSION" >"$tmp" && mv -f "$tmp" "$DC_DIR/store_version"
    rm -f "$tmp"
  fi
  dc_readable
}

# dc_entry_ok <entry dir> <key> <sha256>: the entry is complete and at this
# layout version. Sets DC_RETRIEVED, DC_CTYPE, DC_FORMAT and DC_TITLE (empty
# when none was stored).
dc_entry_ok() {
  local rec
  [[ -f "$1/body" && -f "$1/map.tsv" && -f "$1/meta.json" ]] || return 1
  rec="$(jq -r --argjson v "$DC_STORE_VERSION" --arg k "$2" --arg s "$3" \
    'select(.store_version == $v and .key == $k and .sha256 == $s)
     | [.retrieved, (.content_type // ""), .format, (.title // "" | gsub("[\u001f\r\n]"; " "))]
     | join("\u001f")' "$1/meta.json" 2>/dev/null)"
  rec="${rec%$'\r'}"
  [[ -n "$rec" ]] || return 1
  # shellcheck disable=SC2034 # read by fetch-docs.sh, which sources this file
  IFS=$'\x1f' read -r DC_RETRIEVED DC_CTYPE DC_FORMAT DC_TITLE <<<"$rec"
}

# dc_write_pointer <key> <entry name> [validators]: point the key at the entry,
# validated now (DC_NOW must be set). Sets DC_VALIDATED_EPOCH and DC_VALIDATED.
dc_write_pointer() {
  local ptmp="$DC_DIR/keys/.tmp-${1:0:16}-$$-$RANDOM" line="$2"$'\t'"$DC_NOW"$'\t'"$DC_NOW_ISO"
  [[ -z "${3:-}" ]] || line+=$'\t'"$3"
  if ! { printf '%s\n' "$line" >"$ptmp" && mv -f "$ptmp" "$DC_DIR/keys/${1:0:16}"; }; then
    rm -f "$ptmp"
    return 1
  fi
  # shellcheck disable=SC2034 # read by fetch-docs.sh, which sources this file
  DC_VALIDATED_EPOCH="$DC_NOW" DC_VALIDATED="$DC_NOW_ISO"
}

# dc_validators <accept> <request url> <etag> <last-modified>: print the
# pointer's validators record, or nothing when there is no validator or a value
# holds a separator.
dc_validators() {
  local v
  [[ -n "$3$4" ]] || return 0
  for v in "$@"; do [[ "$v" != *[$'\t\n\r\x1f']* ]] || return 0; done
  printf '%s\x1f%s\x1f%s\x1f%s' "$@"
}

# dc_touch <key>: record the access time; a failed write is ignored.
dc_touch() {
  printf '%s\n' "$DC_NOW" 2>/dev/null >"$DC_DIR/keys/${1:0:16}.access" || true
}

# dc_lookup <key | key-sha256>: resolve a key's pointer once, or name an entry
# directly. On a usable entry set DC_KEY DC_ENTRY DC_VALIDATED_EPOCH
# DC_VALIDATED, DC_QUARANTINED (1 or 0), the validators the pointer holds for
# this entry (DC_ACCEPT DC_REQ_URL DC_ETAG DC_LM, empty when none) and the
# dc_entry_ok fields; otherwise return 1.
dc_lookup() {
  local name="" epoch="" iso="" rest="" key sha
  DC_ACCEPT="" DC_REQ_URL="" DC_ETAG="" DC_LM=""
  dc_readable || return 1
  dc_now
  if [[ "$1" =~ ^([0-9a-f]{64})-([0-9a-f]{64})$ ]]; then
    key="${BASH_REMATCH[1]}" sha="${BASH_REMATCH[2]}"
  elif [[ "$1" =~ ^[0-9a-f]{64}$ ]]; then
    key="$1"
  else
    return 1
  fi
  # The pointer is read once; validated belongs to the entry it names.
  [[ -f "$DC_DIR/keys/${key:0:16}" ]] && IFS=$'\t' read -r name epoch iso rest <"$DC_DIR/keys/${key:0:16}"
  [[ "$epoch" =~ ^[0-9]+$ && -n "$iso" && "$name" == "$key-"* ]] || name="" epoch="" iso="" rest=""
  if [[ -z "${sha:-}" ]]; then
    [[ -n "$name" ]] || return 1
    sha="${name#"$key"-}"
  elif [[ "$name" != "$key-$sha" ]]; then
    epoch="" iso="" rest=""
  fi
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || return 1
  # shellcheck disable=SC2034 # DC_REF is read by fetch-docs.sh, which sources this file
  DC_KEY="$key" DC_ENTRY="$DC_DIR/entries/${key:0:16}-${sha:0:16}" DC_REF="$key-$sha"
  dc_entry_ok "$DC_ENTRY" "$key" "$sha" || return 1
  DC_VALIDATED_EPOCH="$epoch" DC_VALIDATED="$iso"
  # shellcheck disable=SC2034 # read by fetch-docs.sh, which sources this file
  [[ -z "$rest" ]] || IFS=$'\x1f' read -r DC_ACCEPT DC_REQ_URL DC_ETAG DC_LM <<<"$rest"
  # shellcheck disable=SC2034 # read by fetch-docs.sh, which sources this file
  DC_QUARANTINED=0
  # shellcheck disable=SC2034
  [[ ! -f "$DC_DIR/keys/${key:0:16}.quarantine" ]] || DC_QUARANTINED=1
  dc_touch "$key"
}

# dc_confirm <key>-<sha256> [validators]: the fetch confirmed the entry
# current without new bytes (a 304): point the key at it, validated now.
# retrieved and the entry directory are unchanged. Sets the dc_lookup fields.
dc_confirm() {
  [[ "$1" =~ ^[0-9a-f]{64}-[0-9a-f]{64}$ ]] || return 1
  dc_writable && dc_lookup "$1" || return 1
  dc_write_pointer "${1%-*}" "$1" "${2:-}" || return 1
  dc_lookup "$1"
}

# dc_map_file <file>: print the section map of a markdown file.
dc_map_file() {
  local file="$1" sdir nonl=0 rc=0
  sdir="$(mktemp -d)" || return 1
  [[ ! -s "$file" || "$(tail -c 1 "$file" | wc -l | tr -d ' ')" == 1 ]] || nonl=1
  # One file per section's own body, so one hashing process covers every section.
  LC_ALL=C awk -v d="$sdir" -v nonl="$nonl" '
    {
      cum[NR] = cum[NR - 1] + length($0) + 1
      # CommonMark: fences and ATX headings may be indented 0-3 spaces. A fence
      # is 3+ backticks (whose info string holds no backtick) or tildes; only a
      # bare run of the same character, at least as long, closes it.
      line = $0; sub(/\r$/, "", line)
      match(line, /^ */)
      ind = RLENGTH
      rest = substr(line, ind + 1)
      ch = substr(rest, 1, 1)
      run = 0
      if (ind <= 3 && (ch == "`" || ch == "~")) { match(rest, ch == "`" ? "^`+" : "^~+"); run = RLENGTH }
      if (fence != "") {
        if (run >= flen && ch == fence && substr(rest, run + 1) ~ /^[ \t]*$/) fence = ""
        if (n) print > (d "/" n)
        next
      }
      if (run >= 3 && !(ch == "`" && index(substr(rest, run + 1), "`"))) {
        fence = ch; flen = run
      } else if (ind <= 3 && match(rest, /^#+/) && RLENGTH <= 6 && (length(rest) == RLENGTH || substr(rest, RLENGTH + 1, 1) ~ /[ \t]/)) {
        lvl = RLENGTH
        h = substr(rest, RLENGTH + 1)
        gsub(/\t/, " ", h); sub(/[ ]+#+[ ]*$/, "", h); sub(/^[ ]+/, "", h); sub(/[ ]+$/, "", h)
        for (i = n; i >= 1; i--) if (lv[i] >= lvl && !en[i]) en[i] = NR - 1
        if (n) close(d "/" n)
        n++; lv[n] = lvl; st[n] = NR
        path[lvl] = h
        for (i = lvl + 1; i <= 6; i++) path[i] = ""
        p = ""
        for (i = 1; i <= lvl; i++) if (path[i] != "") p = p (p == "" ? "" : " > ") path[i]
        hp[n] = p
        printf "" > (d "/" n)
        next
      }
      if (n) print > (d "/" n)
    }
    END {
      if (n) close(d "/" n)
      for (i = 1; i <= n; i++) {
        if (!en[i]) en[i] = NR
        printf "%d\t%d\t%d\t%d\t%d\t%s\n", i, lv[i], st[i], en[i], cum[en[i]] - cum[st[i] - 1] - (nonl && en[i] == NR), hp[i] > (d "/rows")
      }
    }' "$file" || rc=1
  if [[ $rc -eq 0 && -s "$sdir/rows" ]]; then
    (
      cd "$sdir" || exit 1
      if command -v sha256sum >/dev/null 2>&1; then sha256sum -- [0-9]*; else shasum -a 256 -- [0-9]*; fi
    ) >"$sdir/sums" || rc=1
    # A sum line is `<hex> <name>` or `<hex> *<name>` (binary mode).
    [[ $rc -ne 0 ]] || awk -F'\t' -v OFS='\t' '
      NR == FNR { n = $0; sub(/^[0-9a-f]+ [ *]/, "", n); h[n] = substr($0, 1, 64); next }
      { $6 = h[$1] "\t" $6; print }' "$sdir/sums" "$sdir/rows" || rc=1
  fi
  rm -rf "$sdir"
  return "$rc"
}

# dc_rename_dir <src> <dest>: rename a directory to a name that does not exist
# yet; never move it inside an existing directory. GNU mv -T refuses an
# existing destination; without it the rename is checked and undone.
dc_rename_dir() {
  if [[ -z "${DC_MV_T:-}" ]]; then
    DC_MV_T=0
    mv --version 2>/dev/null | grep -q GNU && DC_MV_T=1
  fi
  if [[ $DC_MV_T -eq 1 ]]; then
    mv -T "$1" "$2" 2>/dev/null
    return
  fi
  [[ ! -e "$2" ]] || return 1
  mv "$1" "$2" 2>/dev/null || return 1
  if [[ -e "$2/${1##*/}" ]]; then
    rm -rf "${2:?}/${1##*/}"
    return 1
  fi
}

# dc_path_fits: the longest path the store writes fits the path limit
# (DOCS_CACHE_PATH_MAX, else 259 where cygpath shows a Windows host, else
# none). Sets DC_ERR when it does not.
dc_path_fits() {
  local max="${DOCS_CACHE_PATH_MAX:-}" native="$DC_DIR" len
  if [[ -z "$max" ]] && command -v cygpath >/dev/null 2>&1; then max=259; fi
  [[ "$max" =~ ^[0-9]+$ ]] || return 0
  if command -v cygpath >/dev/null 2>&1; then
    native="$(cygpath -am "$DC_DIR")"
  elif [[ "$native" != /* ]]; then
    native="$PWD/$native"
  fi
  # /entries/<16 hex>-<16 hex>/meta.json is the longest name below the store.
  local below="/entries/0000000000000000-0000000000000000/meta.json"
  len=$((${#native} + ${#below}))
  [[ $len -gt $max ]] || return 0
  DC_ERR="path too long: entry paths under $native reach $len characters, over the limit of $max"
  return 1
}

# dc_quarantine <key> <new entry name> <new title>: when the key's current
# entry is another one with a different title, record the quarantine.
dc_quarantine() {
  local old="" old_title="" qtmp
  [[ -f "$DC_DIR/keys/${1:0:16}" ]] && IFS=$'\t' read -r old _ <"$DC_DIR/keys/${1:0:16}"
  [[ "$old" =~ ^[0-9a-f]{64}-[0-9a-f]{64}$ && "$old" != "$2" && -n "$3" ]] || return 0
  old_title="$(jq -r '.title // ""' "$DC_DIR/entries/${old:0:16}-${old:65:16}/meta.json" 2>/dev/null)"
  old_title="${old_title%$'\r'}"
  [[ -n "$old_title" && "$old_title" != "$3" ]] || return 0
  qtmp="$DC_DIR/keys/.tmp-${1:0:16}-q-$$-$RANDOM"
  if jq -n --arg at "$DC_NOW_ISO" --arg fe "$old" --arg ft "$old_title" --arg te "$2" --arg tt "$3" \
    '{at: $at, from_entry: $fe, from_title: $ft, to_entry: $te, to_title: $tt}' >"$qtmp"; then
    mv -f "$qtmp" "$DC_DIR/keys/${1:0:16}.quarantine"
  fi
  rm -f "$qtmp"
}

# dc_put <url> <format> <file> [content-type] [title] [validators]: store the
# file's bytes as the key's current entry, validated now. title is recorded
# only when the body has no heading; validators is a dc_validators record.
# Bytes already stored keep their entry and its retrieved time. An entry that
# replaces one with another title quarantines the key. Sets the dc_lookup
# fields; returns 1 when nothing was stored.
dc_put() {
  local url="$1" fmt="$2" src="$3" ctype="${4:-}" title key tmp sha final placed=0
  DC_ERR=""
  [[ -f "$src" ]] || return 1
  dc_path_fits || return 1
  if ! dc_writable; then
    DC_ERR="unwritable, or another store_version"
    return 1
  fi
  dc_now
  key="$(dc_key "$url" "$fmt")"
  tmp="$DC_DIR/entries/.tmp-$$-$RANDOM$RANDOM"
  mkdir "$tmp" || return 1
  if ! { cp "$src" "$tmp/body" && sha="$(dc_sha256 <"$tmp/body")" && dc_map_file "$tmp/body" >"$tmp/map.tsv"; }; then
    rm -rf "$tmp"
    return 1
  fi
  final="$DC_DIR/entries/${key:0:16}-${sha:0:16}"
  if ! dc_entry_ok "$final" "$key" "$sha"; then
    title="$(awk -F'\t' 'NR == 1 { print $7; exit }' "$tmp/map.tsv")"
    [[ -n "$title" ]] || title="${5:-}"
    if ! jq -n --argjson v "$DC_STORE_VERSION" --arg k "$key" --arg u "$url" --arg f "$fmt" --arg s "$sha" \
      --argjson b "$(wc -c <"$tmp/body" | tr -d ' ')" --arg c "$ctype" --arg t "$title" --arg r "$DC_NOW_ISO" \
      'def n: if . == "" then null else . end;
       {store_version: $v, key: $k, url: $u, format: $f, sha256: $s, bytes: $b,
        content_type: ($c | n), title: ($t | n), retrieved: $r}' >"$tmp/meta.json"; then
      rm -rf "$tmp"
      return 1
    fi
    # A writer that lost the race finds the entry in place and its rename fails.
    dc_rename_dir "$tmp" "$final" && placed=1
  fi
  rm -rf "$tmp"
  if ! dc_entry_ok "$final" "$key" "$sha"; then
    # An entry this writer placed and cannot read back is removed, not orphaned.
    [[ $placed -eq 0 ]] || rm -rf "${final:?}"
    DC_ERR="the entry could not be read back from $final"
    return 1
  fi
  dc_quarantine "$key" "$key-$sha" "$DC_TITLE"
  dc_write_pointer "$key" "$key-$sha" "${6:-}" || return 1
  dc_lookup "$key-$sha"
}

# dc_slice_rows <map file> <body file> <id>...: print each section, in the order asked.
dc_slice_rows() {
  local map="$1" body="$2" id range ranges=()
  shift 2
  for id in "$@"; do
    range=""
    [[ ! "$id" =~ ^[1-9][0-9]*$ ]] || range="$(awk -F'\t' -v id="$id" '$1 == id { print $3 "," $4; exit }' "$map")"
    [[ -n "$range" ]] || {
      echo "ERROR: unknown section id: $id" >&2
      return 1
    }
    ranges+=("$range")
  done
  for range in "${ranges[@]}"; do sed -n "${range}p" "$body"; done
}

dc_usage() {
  cat <<'EOF'
docs-cache.sh: store upstream docs pages and return them or their sections.

Usage:
  docs-cache.sh [--cache-dir <dir>] <command> [args]

  key <url> <format>                       print the cache key
  put <url> <format> <file> [content-type] store <file> as the key's current bytes; print the key
  info <ref>                               print the entry's record as JSON
  map (<ref> | --file <path>)              print the section map:
                                           id level start end bytes sha256 heading_path
  slice (<ref> | --file <path>) <id>...    print each section: heading, body and child sections

  <ref> is a key (its current entry) or <key>-<sha256> (that entry).
  --cache-dir <dir>  default: DOCS_CACHE_DIR, else ${XDG_CACHE_HOME:-$HOME/.cache}/claude-docs-cache

Exit: 0 done; 1 miss or unknown section id; 2 fatal.
EOF
}

dc_main() {
  set -uo pipefail
  local dir="" cmd map body tmp rc=0
  if [[ "${1:-}" == --cache-dir ]]; then
    [[ $# -ge 2 && -n "$2" ]] || {
      echo "ERROR: --cache-dir needs a value" >&2
      return 2
    }
    dir="$2"
    shift 2
  fi
  dc_set_dir "$dir"
  cmd="${1:-}"
  shift || true
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq required" >&2
    return 2
  }
  case "$cmd" in
  -h | --help)
    dc_usage
    ;;
  key)
    [[ $# -eq 2 ]] || {
      dc_usage >&2
      return 2
    }
    dc_key "$1" "$2"
    ;;
  put)
    [[ $# -ge 3 && $# -le 4 && -f "$3" ]] || {
      echo "ERROR: put needs <url> <format> <file> [content-type] and an existing file" >&2
      return 2
    }
    dc_put "$@" || {
      echo "ERROR: nothing stored in $DC_DIR (${DC_ERR:-the bytes could not be copied or mapped})" >&2
      return 2
    }
    printf '%s\n' "$DC_KEY"
    ;;
  info)
    [[ $# -eq 1 ]] || {
      dc_usage >&2
      return 2
    }
    dc_lookup "$1" || return 1
    local q=null
    [[ ! -f "$DC_DIR/keys/${DC_KEY:0:16}.quarantine" ]] || q="$(cat "$DC_DIR/keys/${DC_KEY:0:16}.quarantine")"
    jq -c --arg e "$DC_ENTRY" --arg v "$DC_VALIDATED" --arg ve "$DC_VALIDATED_EPOCH" --argjson now "$DC_NOW" \
      --arg et "$DC_ETAG" --arg lm "$DC_LM" --argjson q "$q" \
      'def n: if . == "" then null else . end;
       . + {validated: ($v | n), age_seconds: (if $ve == "" then null else $now - ($ve | tonumber) end),
            etag: ($et | n), last_modified: ($lm | n), quarantine: $q, entry: $e}' "$DC_ENTRY/meta.json"
    ;;
  map | slice)
    if [[ "${1:-}" == --file ]]; then
      [[ $# -ge 2 && -f "$2" ]] || {
        echo "ERROR: --file needs an existing file" >&2
        return 2
      }
      body="$2"
      shift 2
    else
      [[ $# -ge 1 ]] || {
        dc_usage >&2
        return 2
      }
      dc_lookup "$1" || return 1
      body="$DC_ENTRY/body" map="$DC_ENTRY/map.tsv"
      shift
    fi
    if [[ "$cmd" == slice && $# -eq 0 ]]; then
      echo "ERROR: slice needs a section id" >&2
      return 2
    fi
    if [[ -z "${map:-}" ]]; then
      tmp="$(mktemp)" || return 2
      dc_map_file "$body" >"$tmp" || rc=2
      map="$tmp"
    fi
    if [[ $rc -eq 0 ]]; then
      if [[ "$cmd" == map ]]; then cat "$map"; else dc_slice_rows "$map" "$body" "$@" || rc=1; fi
    fi
    [[ -z "${tmp:-}" ]] || rm -f "$tmp"
    return "$rc"
    ;;
  *)
    dc_usage >&2
    return 2
    ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  dc_main "$@"
  exit $?
fi
