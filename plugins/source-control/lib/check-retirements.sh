#!/usr/bin/env bash
# Retired-convention detection and cleanup for a plugin's retirements.yaml.
#
# WHY. When a plugin retires a consumer-facing convention — a config file it no
# longer reads, a gitignore line it no longer recommends, a directory it
# renamed — the old artifact stays behind in every consumer repository. Before
# this helper each plugin detected its own leftovers in bespoke setup prose,
# and the prose drifted. Now the plugin appends one append-only record to its
# retirements.yaml and this helper evaluates every record against the consumer
# repo: setup `check` runs the detection as one fixed step, setup `apply`
# offers the per-record cleanup behind an operator gate. The owner doc is
# docs/conventions/retired-conventions/README.md; this header keeps a named
# operational duplicate of the contract so the executable ships self-described.
#
# MANIFEST. Records separated by a line that is exactly `---`; flat
# `key: value` scalars only (no nesting, no lists); a value may be wrapped in
# single or double quotes (one layer is stripped, nothing inside is escaped).
# Lines starting with `#` and blank lines are ignored. Fields:
#
#   id             <plugin>-rNNN — unique within the manifest, never reused
#   retired        YYYY-MM-DD
#   plugin_version semver of the release that retired the convention
#   kind           file | dir | line
#   path           repo-relative; absolute, `..` segments, a leading `~`,
#                  backslashes, `.` and tabs are rejected
#   match          POSIX ERE — REQUIRED for kind line, forbidden otherwise
#   heading        optional ATX heading (1-6 hashes, whitespace, title), kind
#                  line only: the record only fires when a matching line sits
#                  in that heading's section body, so a standalone occurrence
#                  elsewhere in a markdown file is not a leftover
#   content_match  optional POSIX ERE, kind file only: the record only fires
#                  when the file's content matches, so a path the successor
#                  reuses is not reported as a leftover
#   action         delete | remove-line | migrate — remove-line only with kind
#                  line, delete only with kind file or dir
#   successor      prose the model follows for a migrate — REQUIRED for migrate
#   note           one line, required
#   status         optional; active (default) | report-only (the demotion)
#
# DETECTION. Per kind: file = a regular file exists at path AND (no
# content_match OR it matches); dir = a directory exists; line = the file
# exists AND some line matches `match` (and, when `heading` is set, that line
# sits in the body of a markdown section whose heading line equals `heading`).
# A section runs from the line after that heading through the line before the
# next ATX heading of the same or higher level, or EOF; every such section is
# searched. A trailing carriage return is stripped from every line before
# matching, so a `$`-anchored pattern matches a CRLF-authored file. One TSV
# row per leftover on stdout:
#
#   id<TAB>kind<TAB>path<TAB>action<TAB>status<TAB>note
#
# Paths are emitted exactly as declared — repo-relative, never joined onto the
# root (docs/conventions/windows-path-emit). A human summary goes to stderr.
#
# CLEANUP. `--clean <id>` cleans exactly one record's artifact. delete unlinks
# the file (only if content_match, when declared, still matches) or removes the
# directory (only after re-resolving that it is inside the root and is not the
# root itself). remove-line rewrites the file keeping every non-matching line
# byte-for-byte — each line's own ending survives, so a CRLF file stays CRLF —
# via a temp file in the same directory and a rename. When `heading` is set,
# only matching lines inside that heading's section body are removed. A migrate
# record refuses to clean until `--i-migrated` states that the successor prose
# was followed; it then removes the artifact the way its kind implies.
#
# VALIDATION FAILS THE WHOLE RUN. An invalid record — bad kind, missing match,
# absolute path, duplicate id, migrate without successor, an unknown key — is
# exit 2 before any row is written, naming the record and the field. A skipped
# record would be a leftover nobody hears about, which is the failure this
# helper exists to end.
#
# Usage:
#   check-retirements.sh --manifest <path> [--root <repo>]
#   check-retirements.sh --manifest <path> --clean <id> [--i-migrated] [--root <repo>]
#   check-retirements.sh --help
#
#   --root defaults to ${CLAUDE_PROJECT_DIR}, else the git toplevel, else cwd.
#
# Exit (detect): 0 no active leftover (report-only hits may still be listed);
#                1 at least one active leftover; 2 usage, unreadable manifest,
#                or an invalid record.
# Exit (clean):  0 cleaned; 1 nothing present to clean; 2 usage, invalid
#                record, unknown id, migrate without --i-migrated, or a failed
#                remove/rename (on Windows usually a locked file — close it and
#                re-run; nothing is left half-done).
#
# Shared source: this file is the canonical copy (claude-config) and is synced
# byte-identical into the plugins that carry it by scripts/sync-check-retirements.sh,
# registered in scripts/cross-plugin-source-registry.txt. Bash 3.2-compatible on
# purpose: no associative arrays, no mapfile, no jq, no python.

set -uo pipefail

usage() {
  cat <<'EOF'
check-retirements.sh — detect and clean a plugin's retired conventions.

Evaluates every record of a retirements.yaml against a consumer repository and
prints one TSV row per leftover:

  id<TAB>kind<TAB>path<TAB>action<TAB>status<TAB>note

Usage:
  check-retirements.sh --manifest <path> [--root <repo>]
  check-retirements.sh --manifest <path> --clean <id> [--i-migrated] [--root <repo>]
  check-retirements.sh --help

  --manifest <path>  the plugin's retirements.yaml
  --root <repo>      consumer repository root; defaults to ${CLAUDE_PROJECT_DIR},
                     else the git toplevel, else the current directory
  --clean <id>       clean exactly that record's artifact instead of detecting
  --i-migrated       required with --clean on a migrate record: states that the
                     successor prose was followed, so the artifact may go

Exit (detect): 0 no active leftover; 1 at least one active leftover; 2 usage,
               unreadable manifest, or an invalid record (the whole run fails).
Exit (clean):  0 cleaned; 1 nothing present to clean; 2 error.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

MANIFEST=""
ROOT_ARG=""
CLEAN_ID=""
I_MIGRATED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --manifest)
    [[ $# -ge 2 ]] || die "--manifest needs a path"
    MANIFEST="$2"
    shift 2
    ;;
  --root)
    [[ $# -ge 2 ]] || die "--root needs a path"
    ROOT_ARG="$2"
    shift 2
    ;;
  --clean)
    [[ $# -ge 2 ]] || die "--clean needs a record id"
    CLEAN_ID="$2"
    shift 2
    ;;
  --i-migrated)
    I_MIGRATED=1
    shift
    ;;
  *)
    echo "ERROR: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

[[ -n "$MANIFEST" ]] || die "--manifest is required (see --help)"
[[ -f "$MANIFEST" && -r "$MANIFEST" ]] || die "manifest is not a readable file: $MANIFEST"
if [[ $I_MIGRATED -eq 1 && -z "$CLEAN_ID" ]]; then
  die "--i-migrated only makes sense with --clean <id>"
fi

# tr -d '\r': Git on Windows can return a CRLF-terminated path.
if [[ -n "$ROOT_ARG" ]]; then
  ROOT="$ROOT_ARG"
elif [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  ROOT="$CLAUDE_PROJECT_DIR"
else
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
  [[ -n "$ROOT" ]] || ROOT="$PWD"
fi
[[ -d "$ROOT" ]] || die "--root is not a directory: $ROOT"
ROOT="${ROOT%/}"

# ---------------------------------------------------------------------------
# Manifest parsing — every record is validated before anything is evaluated.
# Parallel indexed arrays rather than one associative array per record: the
# helper has to run on the bash 3.2 that stock macOS ships.
# ---------------------------------------------------------------------------

REC_ID=()
REC_KIND=()
REC_PATH=()
REC_MATCH=()
REC_HEADING=()
REC_CONTENT_MATCH=()
REC_ACTION=()
REC_SUCCESSOR=()
REC_NOTE=()
REC_STATUS=()
REC_COUNT=0
SEEN_IDS="
"

# Built without backslash-bearing literals: shellcheck's SC1003 fires on every
# spelling of one inside quotes.
BACKSLASH=$(printf '%b' '\134')
TAB=$(printf '\t')

# ere_valid <pattern> — 0 when grep -E accepts the pattern. grep exits 2 on a
# malformed expression and 1 on the (expected) no-match against empty input.
ere_valid() {
  local rc=0
  grep -E -e "$1" </dev/null >/dev/null 2>&1 || rc=$?
  [[ $rc -ne 2 ]]
}

# Current record's fields; reset at each `---`.
r_start=0
r_id="" r_retired="" r_plugin_version="" r_kind="" r_path="" r_match=""
r_heading="" r_content_match="" r_action="" r_successor="" r_note="" r_status=""
r_keys=" "
r_nonempty=0

reset_record() {
  r_start=$1
  r_id="" r_retired="" r_plugin_version="" r_kind="" r_path="" r_match=""
  r_heading="" r_content_match="" r_action="" r_successor="" r_note="" r_status=""
  r_keys=" "
  r_nonempty=0
}

# record_label — how a validation message names the record being checked.
record_label() {
  if [[ -n "$r_id" ]]; then
    printf 'record %d (id: %s, line %d)' "$((REC_COUNT + 1))" "$r_id" "$r_start"
  else
    printf 'record %d (line %d)' "$((REC_COUNT + 1))" "$r_start"
  fi
}

invalid() {
  # invalid <field> <message>
  echo "ERROR: $MANIFEST: $(record_label): field '$1' $2" >&2
  exit 2
}

# strip_quotes <value> — remove one layer of matching single or double quotes.
strip_quotes() {
  local v="$1"
  case "$v" in
  \'*\') [[ ${#v} -ge 2 ]] && v="${v#\'}" && v="${v%\'}" ;;
  \"*\") [[ ${#v} -ge 2 ]] && v="${v#\"}" && v="${v%\"}" ;;
  *) ;;
  esac
  printf '%s' "$v"
}

finish_record() {
  [[ $r_nonempty -eq 1 ]] || return 0

  [[ -n "$r_id" ]] || invalid id "is required"
  printf '%s' "$r_id" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?-r[0-9]{3,}$' ||
    invalid id "must be <plugin>-rNNN: '$r_id'"
  case "$SEEN_IDS" in
  *"
$r_id
"*) invalid id "duplicates an earlier record's id: '$r_id'" ;;
  *) ;;
  esac
  SEEN_IDS="${SEEN_IDS}${r_id}
"

  [[ -n "$r_retired" ]] || invalid retired "is required"
  printf '%s' "$r_retired" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ||
    invalid retired "must be YYYY-MM-DD: '$r_retired'"

  [[ -n "$r_plugin_version" ]] || invalid plugin_version "is required"
  printf '%s' "$r_plugin_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$' ||
    invalid plugin_version "must be semver: '$r_plugin_version'"

  case "$r_kind" in
  file | dir | line) ;;
  "") invalid kind "is required" ;;
  *) invalid kind "must be file, dir or line: '$r_kind'" ;;
  esac

  [[ -n "$r_path" ]] || invalid path "is required"
  case "$r_path" in
  /*) invalid path "must be repo-relative, not absolute: '$r_path'" ;;
  [A-Za-z]:*) invalid path "must be repo-relative, not a drive path: '$r_path'" ;;
  '~'*) invalid path "must not start with ~: '$r_path'" ;;
  *"$BACKSLASH"*) invalid path "must use forward slashes: '$r_path'" ;;
  *"$TAB"*) invalid path "must not contain a tab: '$r_path'" ;;
  . | ./ | ./. | */. | */./ | *//*) invalid path "must name a file or directory inside the repo, not the repo itself: '$r_path'" ;;
  *) ;;
  esac
  printf '%s' "$r_path" | grep -Eq '(^|/)\.\.(/|$)' &&
    invalid path "must not contain a .. segment: '$r_path'"

  if [[ "$r_kind" == "line" ]]; then
    [[ -n "$r_match" ]] || invalid match "is required for kind line"
    ere_valid "$r_match" || invalid match "is not a valid POSIX ERE: '$r_match'"
  elif [[ -n "$r_match" ]]; then
    invalid match "is only allowed for kind line (kind is $r_kind)"
  fi

  if [[ -n "$r_heading" ]]; then
    [[ "$r_kind" == "line" ]] || invalid heading "is only allowed for kind line (kind is $r_kind)"
    printf '%s' "$r_heading" | grep -Eq '^#{1,6}[[:space:]]+[^[:space:]]' ||
      invalid heading "must be an ATX heading (1-6 hashes, whitespace, title): '$r_heading'"
  fi

  if [[ -n "$r_content_match" ]]; then
    [[ "$r_kind" == "file" ]] || invalid content_match "is only allowed for kind file (kind is $r_kind)"
    ere_valid "$r_content_match" || invalid content_match "is not a valid POSIX ERE: '$r_content_match'"
  fi

  case "$r_action" in
  delete)
    [[ "$r_kind" != "line" ]] || invalid action "delete is not allowed for kind line (use remove-line)"
    ;;
  remove-line)
    [[ "$r_kind" == "line" ]] || invalid action "remove-line requires kind line (kind is $r_kind)"
    ;;
  migrate)
    [[ -n "$r_successor" ]] || invalid successor "is required for action migrate"
    ;;
  "") invalid action "is required" ;;
  *) invalid action "must be delete, remove-line or migrate: '$r_action'" ;;
  esac

  [[ -n "$r_note" ]] || invalid note "is required"
  case "$r_note" in
  *"$TAB"*) invalid note "must not contain a tab" ;;
  *) ;;
  esac

  case "$r_status" in
  "") r_status="active" ;;
  active | report-only) ;;
  *) invalid status "must be active or report-only: '$r_status'" ;;
  esac

  REC_ID[REC_COUNT]="$r_id"
  REC_KIND[REC_COUNT]="$r_kind"
  REC_PATH[REC_COUNT]="$r_path"
  REC_MATCH[REC_COUNT]="$r_match"
  REC_HEADING[REC_COUNT]="$r_heading"
  REC_CONTENT_MATCH[REC_COUNT]="$r_content_match"
  REC_ACTION[REC_COUNT]="$r_action"
  REC_SUCCESSOR[REC_COUNT]="$r_successor"
  REC_NOTE[REC_COUNT]="$r_note"
  REC_STATUS[REC_COUNT]="$r_status"
  REC_COUNT=$((REC_COUNT + 1))
}

lineno=0
reset_record 1
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  line="${line%$'\r'}"
  case "$line" in
  ---)
    finish_record
    reset_record $((lineno + 1))
    continue
    ;;
  "" | \#*) continue ;;
  *) ;;
  esac
  # Leading whitespace only ever precedes a comment or nothing in a flat
  # manifest; anything else is a nesting attempt and is rejected below.
  case "$line" in
  [[:space:]]*)
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in
    "" | \#*) continue ;;
    *) ;;
    esac
    ;;
  *) ;;
  esac
  if [[ ! "$line" =~ ^([a-z_]+):[[:space:]]*(.*)$ ]]; then
    echo "ERROR: $MANIFEST: $(record_label): line $lineno is not 'key: value': $line" >&2
    exit 2
  fi
  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  value="${value%"${value##*[![:space:]]}"}"
  value="$(strip_quotes "$value")"
  r_nonempty=1
  case "$r_keys" in
  *" $key "*)
    echo "ERROR: $MANIFEST: $(record_label): field '$key' is set twice (line $lineno)" >&2
    exit 2
    ;;
  *) ;;
  esac
  r_keys="${r_keys}${key} "
  case "$key" in
  id) r_id="$value" ;;
  retired) r_retired="$value" ;;
  plugin_version) r_plugin_version="$value" ;;
  kind) r_kind="$value" ;;
  path) r_path="$value" ;;
  match) r_match="$value" ;;
  heading) r_heading="$value" ;;
  content_match) r_content_match="$value" ;;
  action) r_action="$value" ;;
  successor) r_successor="$value" ;;
  note) r_note="$value" ;;
  status) r_status="$value" ;;
  *)
    echo "ERROR: $MANIFEST: $(record_label): field '$key' is not part of the schema (line $lineno)" >&2
    exit 2
    ;;
  esac
done <"$MANIFEST"
finish_record

# ---------------------------------------------------------------------------
# Detection primitives
# ---------------------------------------------------------------------------

# content_hits <file> <ere> — 0 when some line of <file>, its trailing CR
# stripped, matches <ere>. grep is used WITHOUT -q so it drains the pipe: under
# pipefail an early-closing grep would turn awk's SIGPIPE into a failed test.
content_hits() {
  awk '{ sub(/\r$/, ""); print }' "$1" | grep -E -e "$2" >/dev/null
}

# section_body_nrs <file> <heading> — one 1-based line number per line that
# sits in the body of every markdown section whose heading line equals
# <heading> (trailing whitespace ignored on both sides). The heading line
# itself is excluded. A section ends at the next ATX heading of the same or
# higher level, or EOF. POSIX awk only: no interval quantifiers.
section_body_nrs() {
  awk -v heading="$2" '
    function rtrim(s) {
      sub(/[ \t]+$/, "", s)
      return s
    }
    function atx_level(s,   n) {
      n = 0
      while (substr(s, n + 1, 1) == "#") n++
      if (n >= 1 && n <= 6 && substr(s, n + 1, 1) ~ /[ \t]/) return n
      return 0
    }
    {
      sub(/\r$/, "")
      trimmed = rtrim($0)
      if (in_section) {
        lvl = atx_level(trimmed)
        if (lvl > 0 && lvl <= start_level) in_section = 0
      }
      if (in_section == 0 && trimmed == heading) {
        in_section = 1
        start_level = atx_level(trimmed)
        if (start_level == 0) start_level = 6
        next
      }
      if (in_section) print NR
    }
  ' "$1"
}

# matching_line_nrs <file> <ere> [heading] — space-separated 1-based line
# numbers whose text (CR stripped) matches <ere>. When <heading> is non-empty,
# only lines inside that heading's section body.
matching_line_nrs() {
  local file="$1" ere="$2" heading="${3:-}" all scoped n
  all=$(awk '{ sub(/\r$/, ""); print }' "$file" | grep -E -n -e "$ere" | cut -d: -f1 | tr '\n' ' ')
  if [[ -z "$heading" ]]; then
    printf '%s' "$all"
    return
  fi
  scoped=$(section_body_nrs "$file" "$heading" | tr '\n' ' ')
  for n in $all; do
    case " $scoped " in
    *" $n "*) printf '%s ' "$n" ;;
    *) ;;
    esac
  done
}

# present <index> — 0 when record <index>'s artifact is present in ROOT.
present() {
  local i="$1" target nrs
  target="$ROOT/${REC_PATH[$i]}"
  case "${REC_KIND[$i]}" in
  file)
    [[ -f "$target" ]] || return 1
    [[ -z "${REC_CONTENT_MATCH[$i]}" ]] && return 0
    content_hits "$target" "${REC_CONTENT_MATCH[$i]}"
    ;;
  dir)
    [[ -d "$target" ]]
    ;;
  line)
    [[ -f "$target" ]] || return 1
    nrs=$(matching_line_nrs "$target" "${REC_MATCH[$i]}" "${REC_HEADING[$i]}")
    [[ -n "${nrs// /}" ]]
    ;;
  *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Detect mode
# ---------------------------------------------------------------------------

if [[ -z "$CLEAN_ID" ]]; then
  active_hits=0
  report_only_hits=0
  i=0
  while [[ $i -lt $REC_COUNT ]]; do
    if present "$i"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${REC_ID[$i]}" "${REC_KIND[$i]}" "${REC_PATH[$i]}" \
        "${REC_ACTION[$i]}" "${REC_STATUS[$i]}" "${REC_NOTE[$i]}"
      if [[ "${REC_STATUS[$i]}" == "active" ]]; then
        active_hits=$((active_hits + 1))
      else
        report_only_hits=$((report_only_hits + 1))
      fi
    fi
    i=$((i + 1))
  done
  echo "check-retirements: $MANIFEST: $REC_COUNT record(s) evaluated against $ROOT — $active_hits active leftover(s), $report_only_hits report-only." >&2
  [[ $active_hits -eq 0 ]] && exit 0
  exit 1
fi

# ---------------------------------------------------------------------------
# Clean mode
# ---------------------------------------------------------------------------

idx=-1
i=0
while [[ $i -lt $REC_COUNT ]]; do
  if [[ "${REC_ID[$i]}" == "$CLEAN_ID" ]]; then
    idx=$i
    break
  fi
  i=$((i + 1))
done
[[ $idx -ge 0 ]] || die "$MANIFEST has no record with id '$CLEAN_ID'"

kind="${REC_KIND[$idx]}"
path="${REC_PATH[$idx]}"
action="${REC_ACTION[$idx]}"
target="$ROOT/$path"

if [[ "$action" == "migrate" && $I_MIGRATED -eq 0 ]]; then
  echo "ERROR: $CLEAN_ID is a migrate record: its content must be carried over before the artifact goes." >&2
  echo "  successor: ${REC_SUCCESSOR[$idx]}" >&2
  echo "  Re-run with --i-migrated once that is done." >&2
  exit 2
fi

locked_hint="re-run after closing the file (on Windows a locked file makes the remove fail; nothing was changed)"

# File and line cleanup share this: a syntactically clean repo-relative path can
# still walk a symlink parent out of ROOT. Re-resolve at the moment of use.
assert_target_inside_root() {
  local real_root real_parent
  real_root=$(cd "$ROOT" 2>/dev/null && pwd -P) || die "cannot resolve root: $ROOT"
  real_parent=$(cd "$(dirname -- "$target")" 2>/dev/null && pwd -P) || die "cannot resolve $path"
  case "$real_parent" in
  "$real_root" | "$real_root"/*) ;;
  *) die "refusing to remove $path — it resolves outside the repository root ($real_parent)" ;;
  esac
}

if ! present "$idx"; then
  if [[ "$kind" == "file" && -f "$target" && -n "${REC_CONTENT_MATCH[$idx]}" ]]; then
    echo "check-retirements: $CLEAN_ID: $path exists but its content no longer matches the record — the path is in use by something else; nothing to clean." >&2
  else
    echo "check-retirements: $CLEAN_ID: nothing present at $path to clean." >&2
  fi
  exit 1
fi

case "$kind" in
file)
  assert_target_inside_root
  if ! rm -f "$target"; then
    die "could not remove $path — $locked_hint"
  fi
  echo "check-retirements: $CLEAN_ID: removed $path." >&2
  exit 0
  ;;
dir)
  # rm -rf is the one thing here that can do real damage, so the path is
  # re-resolved at the moment of use: it must land strictly inside ROOT and
  # must not be ROOT itself, whatever the manifest text said.
  real_root=$(cd "$ROOT" 2>/dev/null && pwd -P) || die "cannot resolve root: $ROOT"
  real_target=$(cd "$target" 2>/dev/null && pwd -P) || die "cannot resolve $path"
  [[ "$real_target" != "$real_root" ]] || die "refusing to remove $path — it resolves to the repository root"
  case "$real_target" in
  "$real_root"/*) ;;
  *) die "refusing to remove $path — it resolves outside the repository root ($real_target)" ;;
  esac
  if ! rm -rf "$target"; then
    die "could not remove directory $path — $locked_hint"
  fi
  echo "check-retirements: $CLEAN_ID: removed directory $path." >&2
  exit 0
  ;;
line)
  assert_target_inside_root
  match="${REC_MATCH[$idx]}"
  # Which input lines match, by number, decided once by grep -E (the same ERE
  # dialect detection used); when heading is set, only section-body hits
  # count. awk then copies every other line through with its own bytes, CR
  # included. Only the matched lines' text is stripped of the CR, and only
  # for the comparison.
  matched_lines=$(matching_line_nrs "$target" "$match" "${REC_HEADING[$idx]}")
  [[ -n "$matched_lines" ]] || {
    echo "check-retirements: $CLEAN_ID: no line of $path matches; nothing to clean." >&2
    exit 1
  }
  # Whether the original's last line carries a newline: `tail -c 1` prints the
  # final byte and command substitution eats a trailing newline, so an empty
  # result means the file ended with one.
  if [[ -z "$(tail -c 1 "$target")" ]]; then
    ends_with_newline=1
  else
    ends_with_newline=0
  fi
  dir=$(dirname "$target")
  tmp=$(mktemp "$dir/.check-retirements.XXXXXX") || die "could not create a temp file beside $path"
  # cp -p so the rewritten file keeps the original's mode; the content is
  # replaced by the redirect below.
  cp -p "$target" "$tmp" 2>/dev/null || true
  if ! awk -v skip=" $matched_lines" -v nl="$ends_with_newline" '
    { if (index(skip, " " NR " ") > 0) next; kept[++k] = $0; at[k] = NR }
    END {
      for (i = 1; i <= k; i++) {
        printf "%s", kept[i]
        # Every line but the original last one had a newline after it; the
        # last one had it only if the file did.
        if (at[i] < NR || nl) printf "\n"
      }
    }' "$target" >"$tmp"; then
    rm -f "$tmp"
    die "could not rewrite $path — $locked_hint"
  fi
  if ! mv -f "$tmp" "$target"; then
    rm -f "$tmp"
    die "could not replace $path with the rewritten file — $locked_hint"
  fi
  removed=$(printf '%s' "$matched_lines" | wc -w | tr -d ' ')
  echo "check-retirements: $CLEAN_ID: removed $removed line(s) from $path." >&2
  exit 0
  ;;
*) die "unreachable kind: $kind" ;;
esac
