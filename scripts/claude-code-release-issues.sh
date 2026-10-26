#!/usr/bin/env bash
# File one GitHub issue per unread Claude Code release from a
# changelog-status.sh status file.
#
#   scripts/claude-code-release-issues.sh [--dry-run] <status-file>
#   scripts/claude-code-release-issues.sh --help
#
# The status file is what plugins/harness-ops/skills/changelog/scripts/
# changelog-status.sh prints (its header, "Output"). The whole file is checked
# before any gh call:
#   - `range: up to date` files nothing.
#   - `range: not computed (...)` or `last-applied: none` exits 2 and files
#     nothing: an unread changelog or a missing marker is never "nothing unread".
#   - `cap: within budget` files one issue per version on the `releases:` line,
#     titled `Claude Code changelog: <X.Y.Z>`, unless an issue with exactly that
#     title exists in any state.
#   - `cap: exceeded` files no per-release issue. It files one issue titled
#     `Claude Code changelog: unread releases beyond the replay cap` holding the
#     `recommend:` line, unless an open issue with that title exists.
#   - Any other shape, or a version that is not X.Y.Z, exits 2.
#
# Titles are matched exactly in jq over one `gh issue list --state all` search
# for the shared title prefix, read only when something would be filed. Search,
# not a creator-filtered list, because an issue anyone filed with the title
# counts; the run is daily and serialized, so search index lag cannot race it.
# Bodies
# are written to a temp file and passed with --body-file. No labels, assignees
# or mentions: the issue proposes, it never admits.
#
# --dry-run makes only the issue list read. Every run prints one
# `action=<create|none> title=<title>` line per title it considers.
# The run URL comes from GITHUB_SERVER_URL, GITHUB_REPOSITORY and GITHUB_RUN_ID.
#
# Exit: 0 success, 1 any failed gh call (a failed list read stops the run;
# after a failed create the other releases still run), 2 usage, unreadable or
# malformed status, range not computed, no read marker, or jq missing.
set -uo pipefail
export LC_ALL=C

SELF="claude-code-release-issues"
PREFIX="Claude Code changelog: "
CAP_TITLE="${PREFIX}unread releases beyond the replay cap"
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

usage() {
  printf 'usage: %s [--dry-run] <status-file> | --help\n' "${0##*/}"
}

die() {
  printf '%s: %s\n' "$SELF" "$*" >&2
  exit 2
}

DRY=0
STATUS=""
while (($# > 0)); do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --dry-run) DRY=1 ;;
  -*)
    usage >&2
    exit 2
    ;;
  *)
    [[ -z "$STATUS" ]] || {
      usage >&2
      exit 2
    }
    STATUS="$1"
    ;;
  esac
  shift
done
[[ -n "$STATUS" ]] || {
  usage >&2
  exit 2
}
[[ -f "$STATUS" && -r "$STATUS" ]] || die "cannot read status file: $STATUS"
command -v jq >/dev/null 2>&1 || die "jq is required"

# value <key>: the text after the first `<key>: ` line, empty when absent.
value() { sed -n "s/^$1: //p" "$STATUS" | head -1 | tr -d '\r'; }

# span <text>: the text as one markdown code span, backticks replaced.
span() {
  local s="$1"
  # shellcheck disable=SC2016  # the backticks are the literal span delimiters
  printf '`%s`' "${s//\`/\'}"
}

# --- parse -------------------------------------------------------------------

last="$(value last-applied)"
range="$(value range)"
cap="$(value cap)"
releases="$(value releases)"
recommend="$(value recommend)"

[[ -n "$range" ]] || die "no range line in $STATUS"
[[ "$range" == "not computed"* ]] && die "range $range; nothing filed"
[[ -n "$last" && "$last" != none ]] || die "no read marker (last-applied: ${last:-absent}); nothing filed"
[[ "$last" =~ $VERSION_RE ]] || die "last-applied is not X.Y.Z: $last"
if [[ "$range" == "up to date" ]]; then
  printf 'action=none title=(up to date at %s)\n' "$last"
  exit 0
fi
[[ "$range" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.\.([0-9]+\.[0-9]+\.[0-9]+)\  ]] || die "range line not in A..B form: $range"
span_range="${BASH_REMATCH[1]}..${BASH_REMATCH[2]}"

TITLES=()
case "$cap" in
"exceeded "*)
  [[ -n "$recommend" ]] || die "cap exceeded with no recommend line"
  TITLES=("$CAP_TITLE")
  ;;
"within budget "*)
  [[ -n "$releases" ]] || die "no releases line in $STATUS"
  for v in $releases; do
    [[ "$v" =~ $VERSION_RE ]] || die "release is not X.Y.Z: $v"
    TITLES+=("$PREFIX$v")
  done
  ;;
*) die "cap line missing or unknown: ${cap:-absent}" ;;
esac

# --- act ---------------------------------------------------------------------

RUN_DATE="$(date -u +%Y-%m-%d)"
RUN_URL="(local run, no run URL)"
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  RUN_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
fi

TMPDIR_RUN="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

if ! ISSUES="$(gh issue list --state all --search "in:title \"${PREFIX% }\"" --limit 1000 --json number,title,state)"; then
  printf '%s: issue list failed\n' "$SELF" >&2
  exit 1
fi
jq -e 'type == "array"' >/dev/null 2>&1 <<<"$ISSUES" || {
  printf '%s: unreadable issue list\n' "$SELF" >&2
  exit 1
}

# exists <title> <any|open>: 0 when an issue with exactly that title exists.
exists() {
  jq -e --arg t "$1" --arg s "$2" \
    'any(.[]; .title == $t and ($s == "any" or (.state | ascii_downcase) == "open"))' >/dev/null <<<"$ISSUES"
}

write_body() { # <title> <file>
  local body v
  body="Run: $RUN_DATE, $RUN_URL"$'\n\n'
  if [[ "$1" == "$CAP_TITLE" ]]; then
    body+="The unread Claude Code releases $(span "$span_range") exceed the replay cap of \`/harness-ops:changelog\`, read from marker $(span "$last") in \`docs/upstream/claude-code.md\`. Its status script recommends:"$'\n\n'
    body+='```text'$'\n'"recommend: ${recommend//\`/\'}"$'\n''```'$'\n\n'
    body+="Do that instead of a release-by-release replay. Moving the marker makes the next run file per-release issues again."$'\n'
  else
    v="${1#"$PREFIX"}"
    body+="Claude Code $(span "$v") is published, and this repository's read marker in \`docs/upstream/claude-code.md\` is at $(span "$last")."$'\n\n'
    body+="Run $(span "/harness-ops:changelog apply v$v") over it, then move the marker."$'\n'
  fi
  printf '%s' "$body" >"$2"
}

failed=0
i=0
for title in "${TITLES[@]}"; do
  i=$((i + 1))
  if [[ "$title" == "$CAP_TITLE" ]]; then scope=open; else scope=any; fi
  if exists "$title" "$scope"; then
    printf 'action=none title=%s\n' "$title"
    continue
  fi
  printf 'action=create title=%s\n' "$title"
  ((DRY)) && continue
  body_file="$TMPDIR_RUN/body-$i.md"
  write_body "$title" "$body_file"
  gh issue create --title "$title" --body-file "$body_file" >/dev/null || {
    printf '%s: issue create failed for %s\n' "$SELF" "$title" >&2
    failed=1
  }
done

exit "$failed"
