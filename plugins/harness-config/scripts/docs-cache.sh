#!/usr/bin/env bash
# GENERATED from lib/docs-cache.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# Upstream docs cache, shared by the plugins that read vendor docs pages.
#
# fetch-docs.sh sources this file for --cache; the CLI below reads what it
# stored. The cache stores page bytes, validates them and returns them or
# their sections. It never decides which section is relevant: the caller
# names the sections it wants.
#
# Store layout under the cache directory (every name derived from a URL is a
# hex digest, so paths stay short on Windows):
#   store_version          the layout version; a reader that meets another
#                          version treats the store as empty and a writer
#                          refuses to write
#   entries/<key>-<sha256> one immutable entry: body (the raw bytes), meta.json
#                          and map.tsv. It is built in a .tmp-* directory beside
#                          it and renamed into place complete, and never
#                          modified after.
#   keys/<key>             the key's pointer: one line, the current entry's name,
#                          the validated epoch and the validated UTC ISO time.
#                          It is switched by writing a temp file and renaming it
#                          over the old one; a reader reads it once and then
#                          only the entry it named.
#   keys/<key>.access      last access epoch, written best-effort on every
#                          read and write
#
# key is sha256 of the normalized URL (scheme and host lower-cased, fragment
# dropped), a newline and the format. meta.json holds store_version, key, url,
# format, sha256 (of body), bytes, content_type and retrieved (when these bytes
# were first stored). validated (when they were last confirmed current) lives
# in the pointer, so confirming unchanged bytes rewrites only the pointer.
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

DC_STORE_VERSION=1

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
# layout version. Sets DC_RETRIEVED and DC_CTYPE (empty when none was stored).
dc_entry_ok() {
  local rec
  [[ -f "$1/body" && -f "$1/map.tsv" && -f "$1/meta.json" ]] || return 1
  rec="$(jq -r --argjson v "$DC_STORE_VERSION" --arg k "$2" --arg s "$3" \
    'select(.store_version == $v and .key == $k and .sha256 == $s)
     | [.retrieved, (.content_type // "")] | join("\u001f")' "$1/meta.json" 2>/dev/null)"
  [[ -n "$rec" ]] || return 1
  # shellcheck disable=SC2034 # read by fetch-docs.sh, which sources this file
  IFS=$'\x1f' read -r DC_RETRIEVED DC_CTYPE <<<"$rec"
}

# dc_touch <key>: record the access time; a failed write is ignored.
dc_touch() {
  printf '%s\n' "$DC_NOW" 2>/dev/null >"$DC_DIR/keys/$1.access" || true
}

# dc_lookup <key | key-sha256>: resolve a key's pointer once, or name an entry
# directly. On a usable entry set DC_KEY DC_ENTRY DC_VALIDATED_EPOCH
# DC_VALIDATED and the dc_entry_ok fields; otherwise return 1.
dc_lookup() {
  local name="" epoch="" iso="" key sha
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
  [[ -f "$DC_DIR/keys/$key" ]] && IFS=$'\t' read -r name epoch iso <"$DC_DIR/keys/$key"
  [[ "$epoch" =~ ^[0-9]+$ && -n "$iso" && "$name" == "$key-"* ]] || name="" epoch="" iso=""
  if [[ -z "${sha:-}" ]]; then
    [[ -n "$name" ]] || return 1
    sha="${name#"$key"-}"
  elif [[ "$name" != "$key-$sha" ]]; then
    epoch="" iso=""
  fi
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || return 1
  DC_KEY="$key" DC_ENTRY="$DC_DIR/entries/$key-$sha"
  dc_entry_ok "$DC_ENTRY" "$key" "$sha" || return 1
  DC_VALIDATED_EPOCH="$epoch" DC_VALIDATED="$iso"
  dc_touch "$key"
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
      if (match($0, /^[ \t]*(```|~~~)/)) {
        m = substr($0, RSTART + RLENGTH - 3, 3)
        if (fence == "") fence = m; else if (m == fence) fence = ""
      } else if (fence == "" && match($0, /^#+[ \t]/) && RLENGTH <= 7) {
        lvl = RLENGTH - 1
        h = substr($0, RLENGTH + 1)
        gsub(/\t/, " ", h); sub(/\r$/, "", h); sub(/[ ]+#+[ ]*$/, "", h); sub(/^[ ]+/, "", h); sub(/[ ]+$/, "", h)
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

# dc_put <url> <format> <file> [content-type]: store the file's bytes as the
# key's current entry, validated now. Bytes already stored keep their entry and
# its retrieved time. Sets DC_KEY DC_ENTRY DC_RETRIEVED DC_VALIDATED
# DC_VALIDATED_EPOCH; returns 1 when nothing was stored.
dc_put() {
  local url="$1" fmt="$2" src="$3" ctype="${4:-}" key tmp sha final ptmp
  [[ -f "$src" ]] || return 1
  dc_writable || return 1
  dc_now
  key="$(dc_key "$url" "$fmt")"
  tmp="$DC_DIR/entries/.tmp-$$-$RANDOM$RANDOM"
  mkdir "$tmp" || return 1
  if ! { cp "$src" "$tmp/body" && sha="$(dc_sha256 <"$tmp/body")" && dc_map_file "$tmp/body" >"$tmp/map.tsv"; }; then
    rm -rf "$tmp"
    return 1
  fi
  final="$DC_DIR/entries/$key-$sha"
  if ! dc_entry_ok "$final" "$key" "$sha"; then
    if ! jq -n --argjson v "$DC_STORE_VERSION" --arg k "$key" --arg u "$url" --arg f "$fmt" --arg s "$sha" \
      --argjson b "$(wc -c <"$tmp/body" | tr -d ' ')" --arg c "$ctype" --arg r "$DC_NOW_ISO" \
      '{store_version: $v, key: $k, url: $u, format: $f, sha256: $s, bytes: $b,
        content_type: (if $c == "" then null else $c end), retrieved: $r}' >"$tmp/meta.json"; then
      rm -rf "$tmp"
      return 1
    fi
    # A writer that lost the race finds the entry in place: mv then moves its
    # temp directory inside the winner's, and the next line removes it.
    mv "$tmp" "$final" 2>/dev/null
    rm -rf "${final:?}/${tmp##*/}"
  fi
  rm -rf "$tmp"
  dc_entry_ok "$final" "$key" "$sha" || return 1
  ptmp="$DC_DIR/keys/.tmp-$key-$$-$RANDOM"
  if ! { printf '%s\t%s\t%s\n' "$key-$sha" "$DC_NOW" "$DC_NOW_ISO" >"$ptmp" && mv -f "$ptmp" "$DC_DIR/keys/$key"; }; then
    rm -f "$ptmp"
    return 1
  fi
  DC_KEY="$key" DC_ENTRY="$final" DC_VALIDATED_EPOCH="$DC_NOW" DC_VALIDATED="$DC_NOW_ISO"
  dc_touch "$key"
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
      echo "ERROR: nothing stored in $DC_DIR (unwritable, or another store_version)" >&2
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
    jq -c --arg e "$DC_ENTRY" --arg v "$DC_VALIDATED" --arg ve "$DC_VALIDATED_EPOCH" --argjson now "$DC_NOW" \
      '. + {validated: (if $v == "" then null else $v end),
            age_seconds: (if $ve == "" then null else $now - ($ve | tonumber) end), entry: $e}' "$DC_ENTRY/meta.json"
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
