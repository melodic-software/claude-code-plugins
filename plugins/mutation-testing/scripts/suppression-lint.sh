#!/usr/bin/env bash
# Exit 0 = every entry passed both derivations and carries all five keys. An
#          ABSENT record and a record whose `suppressions:` mapping is empty are
#          both exit 0: no suppressions is a valid state for this surface.
# Exit 1 = at least one entry is malformed, mismatched, or binds a kind outside
#          the vocabulary.
# Exit 2 = usage error, a record present but carrying no top-level
#          `suppressions:` mapping, an unreadable or empty vocabulary table, or
#          no digest tool. FAIL CLOSED: a record this script cannot grade never
#          reports as clean.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_KINDS="$SCRIPT_DIR/../skills/principles/reference/scaling-and-suppression.md"
US=$'\037'
TAB=$'\t'

usage() {
  cat <<'EOF'
Validate an arid-node suppression record: re-derive each entry's finding_id and check its kind against the vocabulary table.

Usage:
  bash suppression-lint.sh <record> [<record> ...]
  bash suppression-lint.sh --kinds <file> <record> [<record> ...]
  bash suppression-lint.sh --help

  <record>        a record file; `-` reads stdin
  --kinds <file>  vocabulary table (default: skills/principles/reference/scaling-and-suppression.md)
  --help          print this help

Exit 0 = every entry passed, or no suppressions; 1 = an entry is malformed, mismatched or
binds an unknown kind; 2 = usage error, a record with no `suppressions:` mapping, an
unreadable vocabulary table, or no digest tool.
EOF
}

die() {
  printf 'suppression-lint: %s\n' "$1" >&2
  exit 2
}

is_calendar_iso_date() {
  local y m d max
  [[ "$1" =~ ^([0-9]{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] || return 1
  y=$((10#${BASH_REMATCH[1]}))
  m=$((10#${BASH_REMATCH[2]}))
  d=$((10#${BASH_REMATCH[3]}))
  case "$m" in
  1 | 3 | 5 | 7 | 8 | 10 | 12) max=31 ;;
  4 | 6 | 9 | 11) max=30 ;;
  2)
    if ((y % 400 == 0 || (y % 4 == 0 && y % 100 != 0))); then
      max=29
    else
      max=28
    fi
    ;;
  *) return 1 ;;
  esac
  ((d >= 1 && d <= max))
}

digest16() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(printf '%s' "$1" | sha256sum)"
  elif command -v shasum >/dev/null 2>&1; then
    out="$(printf '%s' "$1" | shasum -a 256)"
  else
    return 2
  fi
  printf '%s' "${out:0:16}"
}

read_kinds() {
  awk '
    /^#### The node-kind vocabulary/ { inv = 1; next }
    inv && /^#/ { exit }
    inv && /^\|/ {
      line = $0
      sub(/^\|[ \t]*/, "", line)
      bar = index(line, "|")
      if (bar == 0) next
      cell = substr(line, 1, bar - 1)
      gsub(/[ \t`]/, "", cell)
      if (cell == "" || cell == "kind") next
      if (cell ~ /^-+$/) next
      print cell
    }
  ' "$1"
}

parse_record() {
  awk -v tab="$TAB" '
    BEGIN { entry_indent = -1 }
    function unquote(v,   f, l) {
      if (length(v) >= 2) {
        f = substr(v, 1, 1)
        l = substr(v, length(v), 1)
        if ((f == "\"" && l == "\"") || (f == "'"'"'" && l == "'"'"'"))
          return substr(v, 2, length(v) - 2)
      }
      return v
    }
    function clean(v) {
      sub(/^[ \t]+/, "", v)
      sub(/[ \t]+$/, "", v)
      return unquote(v)
    }
    function err(msg) {
      if (entry_open) printf "X%s%s\n", tab, msg
      else printf "F%s%s\n", tab, msg
    }
    function flush_site() {
      if (!site_open) return
      site_open = 0
      if (site_surface == "") { err("a site carries no surface"); return }
      if (best_v < 0) { err("site " site_surface " carries no anchor/v<N>"); return }
      printf "S%s%s%s%s\n", tab, site_surface, tab, best_anchor
    }
    function open_site() {
      flush_site()
      site_open = 1; site_surface = ""; best_anchor = ""; best_v = -1
    }
    function close_entry() {
      flush_site()
      in_sites = 0
      entry_open = 0
    }
    function site_key(k, v,   n) {
      if (k == "surface") { site_surface = v; return }
      if (k ~ /^anchor\/v[0-9]+$/) {
        n = k; sub(/^anchor\/v/, "", n); n = n + 0
        if (n > best_v) { best_v = n; best_anchor = v }
        return
      }
      err("site key " k " is not surface or anchor/v<N>")
    }
    function scalar(body,   p, k, v) {
      p = index(body, ":")
      if (p == 0) { err("line is not a key: value pair: " body); return }
      k = substr(body, 1, p - 1)
      v = clean(substr(body, p + 1))
      sub(/[ \t]+$/, "", k)
      if (index(k, tab) || index(v, tab)) { err("a tab inside key " k); return }
      if (in_sites) { site_key(k, v); return }
      if (k == "sites") { in_sites = 1; sites_indent = cur_indent; return }
      printf "K%s%s%s%s\n", tab, k, tab, v
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[ \t]*$/) next
      if (line ~ /^[ \t]*```/) next
      if (line ~ /^[ \t]*#/) next
      cur_indent = match(line, /[^ ]/) - 1
      body = substr(line, cur_indent + 1)
      if (substr(body, 1, 1) == "\t") { err("tab indentation is not YAML"); next }

      if (!found) {
        if (cur_indent == 0 && body ~ /^suppressions:[ \t]*(\{\}[ \t]*)?$/) {
          found = 1
          if (body ~ /\{\}/) done = 1
        }
        next
      }
      if (done) next
      if (cur_indent == 0) { close_entry(); done = 1; next }

      if (entry_indent < 0) entry_indent = cur_indent
      if (cur_indent < entry_indent) { err("indentation below the entry level"); next }

      if (cur_indent == entry_indent) {
        close_entry()
        if (body !~ /^[^ :]+:[ \t]*$/) { printf "F%s%s\n", tab, "entry key is not <finding_id>:  " body; next }
        id = body; sub(/:[ \t]*$/, "", id)
        entry_open = 1
        printf "E%s%s\n", tab, id
        next
      }

      if (!entry_open) { err("content before any entry"); next }

      if (in_sites && cur_indent <= sites_indent) { flush_site(); in_sites = 0 }

      if (in_sites && body ~ /^-/) {
        open_site()
        rest = body
        sub(/^-[ \t]*/, "", rest)
        if (rest != "") scalar(rest)
        next
      }
      scalar(body)
    }
    END { close_entry() }
  ' "$1"
}

kinds_file="$DEFAULT_KINDS"
records=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --kinds)
    [[ $# -ge 2 ]] || die "--kinds needs a file"
    kinds_file="$2"
    shift 2
    ;;
  --)
    shift
    [[ $# -eq 0 ]] || records+=("$@")
    break
    ;;
  -?*)
    die "unknown argument: $1"
    ;;
  *)
    records+=("$1")
    shift
    ;;
  esac
done

[[ ${#records[@]} -gt 0 ]] || die "no record given; see --help"
digest16 probe >/dev/null || die "neither sha256sum nor shasum is available"
[[ -r "$kinds_file" ]] || die "vocabulary table is not readable: $kinds_file"

kinds="$(read_kinds "$kinds_file")"
[[ -n "$kinds" ]] || die "no node kinds found in $kinds_file"
kinds_flat="${kinds//$'\n'/ }"
kinds_list="${kinds//$'\n'/, }"

is_kind() {
  case " $kinds_flat " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

entries=0
ok_count=0
failed=0
kind_failure=0

grade_entry() {
  [[ -n "$cur_id" ]] || return 0
  entries=$((entries + 1))

  local missing="" failures="" verdict="" detail=""
  [[ -n "$has_check" ]] || missing="check"
  [[ -n "$has_claim" ]] || missing="${missing:+$missing, }claim"
  [[ "$site_count" -gt 0 ]] || missing="${missing:+$missing, }sites"
  [[ -n "$has_reason" ]] || missing="${missing:+$missing, }reason"
  [[ -n "$has_date" ]] || missing="${missing:+$missing, }date"

  [[ -z "$missing" ]] || failures="missing required key(s): $missing"
  [[ -z "$cur_defects" ]] || failures="${failures:+$failures; }$cur_defects"

  if [[ -n "$failures" ]]; then
    verdict="malformed"
    detail="$failures"
  fi

  local derived=""
  if [[ -n "$has_check" && -n "$has_claim" && "$site_count" -gt 0 ]]; then
    local joined="$cur_check$US$cur_claim" surface anchor
    while IFS="$TAB" read -r surface anchor; do
      [[ -n "$surface" ]] || continue
      joined="$joined$US$surface$US$anchor"
    done < <(printf '%s' "$cur_sites" | LC_ALL=C sort)
    derived="$(digest16 "$joined")"
    if [[ "$derived" != "$cur_id" ]]; then
      [[ -n "$verdict" ]] || verdict="mismatch"
      detail="${detail:+$detail; }constituents hash to $derived"
    fi
  fi

  if [[ -n "$has_claim" ]]; then
    local kind=""
    if [[ "$cur_claim" == "arid(kind="*")" ]]; then
      kind="${cur_claim#arid(kind=}"
      kind="${kind%)}"
    fi
    if [[ -z "$kind" ]]; then
      [[ -n "$verdict" ]] || verdict="malformed"
      detail="${detail:+$detail; }claim is not the canonical arid(kind=<node-kind>)"
    elif ! is_kind "$kind"; then
      [[ -n "$verdict" ]] || verdict="unknown-kind"
      detail="${detail:+$detail; }claim binds kind=$kind, not in the vocabulary"
      kind_failure=1
    fi
  fi

  if [[ -n "$verdict" ]]; then
    printf '%s %s %s\n' "$verdict" "$cur_id" "$detail"
    failed=$((failed + 1))
  else
    printf 'ok %s\n' "$cur_id"
    ok_count=$((ok_count + 1))
  fi
}

reset_entry() {
  cur_id=""
  cur_check=""
  cur_claim=""
  cur_sites=""
  cur_defects=""
  has_check=""
  has_claim=""
  has_reason=""
  has_date=""
  site_count=0
}

reset_entry

stdin_copy=""
trap '[[ -z "$stdin_copy" ]] || rm -f "$stdin_copy"' EXIT

for record in "${records[@]}"; do
  printf 'record %s\n' "$record"
  path="$record"
  if [[ "$record" == "-" ]]; then
    stdin_copy="$(mktemp)" || die "cannot buffer stdin"
    cat >"$stdin_copy"
    path="$stdin_copy"
  elif [[ ! -e "$record" ]]; then
    printf 'absent %s\n' "$record"
    continue
  fi
  [[ -r "$path" ]] || die "record is not readable: $record"

  stream="$(parse_record "$path")"
  if grep -q "^F$TAB" <<<"$stream"; then
    printf '%s\n' "$stream" | sed -n "s/^F$TAB/unparseable: /p" >&2
    die "cannot grade $record"
  fi
  if [[ -z "$stream" ]]; then
    if grep -q '^suppressions:' "$path"; then
      continue
    fi
    die "no top-level suppressions: mapping in $record"
  fi

  while IFS="$TAB" read -r tag f1 f2; do
    case "$tag" in
    E)
      grade_entry
      reset_entry
      cur_id="$f1"
      ;;
    K)
      case "$f1" in
      check)
        cur_check="$f2"
        has_check=1
        ;;
      claim)
        cur_claim="$f2"
        has_claim=1
        ;;
      reason) [[ -z "$f2" ]] || has_reason=1 ;;
      date)
        if [[ -n "$f2" ]]; then
          has_date=1
          is_calendar_iso_date "$f2" ||
            cur_defects="${cur_defects:+$cur_defects; }date is not ISO-8601 (YYYY-MM-DD): $f2"
        fi
        ;;
      *) cur_defects="${cur_defects:+$cur_defects; }unrecognized key: $f1" ;;
      esac
      ;;
    S)
      cur_sites="${cur_sites:+$cur_sites
}$f1$TAB$f2"
      site_count=$((site_count + 1))
      ;;
    X) cur_defects="${cur_defects:+$cur_defects; }$f1" ;;
    *) ;;
    esac
  done <<<"$stream"
  grade_entry
  reset_entry
done

[[ "$kind_failure" -eq 0 ]] || printf 'accepted kinds: %s\n' "$kinds_list"
printf 'suppression-lint: entries=%d ok=%d failed=%d\n' "$entries" "$ok_count" "$failed"
[[ "$failed" -eq 0 ]] || exit 1
exit 0
