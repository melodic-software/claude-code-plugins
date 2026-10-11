#!/usr/bin/env bash
# Keep one GitHub issue per drifted upstream from a check-upstream-drift.sh
# --report file.
#
#   scripts/upstream-drift-issues.sh [--dry-run] <report-file>
#   scripts/upstream-drift-issues.sh --help
#
# Each upstream repository gets at most one open issue titled
# `Upstream drift: <owner>/<repo>`, found with `gh issue list` and an exact
# title match in jq. A repository with a drifted page gets that issue created,
# or its body replaced in place; a repository whose pages are all clean gets
# an open issue closed with a comment; a repository whose pages are all
# `untracked` is left alone. The body names the pin, head, run date and run URL,
# then one line per changed row or unit, every report-derived string inside a
# code span with backticks replaced. It is cut at 60,000 characters with a
# pointer to the run's job summary, written to a temp file and passed with
# --body-file. No labels, assignees or mentions.
#
# The whole report is parsed before any gh call. Each line follows the fixed
# field order of the report (docs/conventions/upstream-drift/README.md, the
# --report row): the path is everything after the first ` path=`. A line that
# breaks the order exits 2 with no gh call.
#
# --dry-run makes only the `gh issue list` reads. Every run prints one
# `action=<create|edit|close|none> repo=<owner>/<repo>` line per repository.
# The run URL comes from GITHUB_SERVER_URL, GITHUB_REPOSITORY and GITHUB_RUN_ID.
#
# Exit: 0 success, 1 any failed gh call (the other repositories still run),
# 2 usage, unreadable or malformed report, or jq missing.
set -uo pipefail
export LC_ALL=C

SELF="upstream-drift-issues"
CAP=60000

usage() {
  printf 'usage: %s [--dry-run] <report-file> | --help\n' "${0##*/}"
}

die() {
  printf '%s: %s\n' "$SELF" "$*" >&2
  exit 2
}

DRY=0
REPORT=""
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
    [[ -z "$REPORT" ]] || {
      usage >&2
      exit 2
    }
    REPORT="$1"
    ;;
  esac
  shift
done
[[ -n "$REPORT" ]] || {
  usage >&2
  exit 2
}
[[ -f "$REPORT" && -r "$REPORT" ]] || die "cannot read report file: $REPORT"
command -v jq >/dev/null 2>&1 || die "jq is required"

# span <text>: the text as one markdown code span, backticks replaced.
span() {
  local s="$1"
  # shellcheck disable=SC2016  # the backticks are the literal span delimiters
  printf '`%s`' "${s//\`/\'}"
}

# --- parse -------------------------------------------------------------------

REPOS=()  # repository per index, first-seen order
STATE=()  # none | clean | drift
DETAIL=() # body lines for drifted pages
repo_index=-1
page_status=""

find_repo() { # <owner/repo>: sets repo_index, adding the repository if new
  local i
  for i in "${!REPOS[@]}"; do
    if [[ "${REPOS[i]}" == "$1" ]]; then
      repo_index=$i
      return 0
    fi
  done
  REPOS+=("$1")
  STATE+=(none)
  DETAIL+=("")
  repo_index=$((${#REPOS[@]} - 1))
}

re_page='^page repo=([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) pin=([0-9a-f]+) head=([0-9a-f]+) status=(untracked|clean|drift) path=(.+)$'
re_row='^row line=([0-9]+) status=([A-Za-z]+) path=(.+)$'
re_unit='^(new|removed)-unit path=(.+)$'

lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  if [[ "$line" =~ $re_page ]]; then
    repo="${BASH_REMATCH[1]}" pin="${BASH_REMATCH[2]}" head="${BASH_REMATCH[3]}"
    page_status="${BASH_REMATCH[4]}" page="${BASH_REMATCH[5]}"
    find_repo "$repo"
    case "$page_status" in
    drift)
      STATE[repo_index]=drift
      DETAIL[repo_index]+=$'\n'"### $(span "$page")"$'\n\n'"Pin $(span "$pin"), upstream head $(span "$head")."$'\n\n'
      ;;
    clean) [[ "${STATE[repo_index]}" == drift ]] || STATE[repo_index]=clean ;;
    *) ;; # untracked: the repository is listed, nothing is written
    esac
  elif ((repo_index >= 0)) && [[ "$line" =~ $re_row ]]; then
    n="${BASH_REMATCH[1]}" st="${BASH_REMATCH[2]}" p="${BASH_REMATCH[3]}"
    [[ "$page_status" == drift && "$st" != unchanged ]] &&
      DETAIL[repo_index]+="- $(span "$st") $(span "$p") (page line $n)"$'\n'
  elif ((repo_index >= 0)) && [[ "$line" =~ $re_unit ]]; then
    kind="${BASH_REMATCH[1]}" p="${BASH_REMATCH[2]}"
    [[ "$page_status" == drift ]] &&
      DETAIL[repo_index]+="- $kind unit $(span "$p")"$'\n'
  else
    die "$REPORT:$lineno: line does not follow the report field order"
  fi
done <"$REPORT"

# --- act ---------------------------------------------------------------------

RUN_DATE="$(date -u +%Y-%m-%d)"
RUN_URL="(local run, no run URL)"
if [[ -n "${GITHUB_SERVER_URL:-}" && -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_RUN_ID:-}" ]]; then
  RUN_URL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
fi

TMPDIR_RUN="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

failed=0

# open_issue <title>: prints the number of the open issue with exactly that
# title, or nothing; returns 1 when the list call fails.
open_issue() {
  local json num
  json="$(gh issue list --state open --search "in:title \"$1\"" --json number,title)" || return 1
  num="$(jq -r --arg t "$1" '[.[] | select(.title == $t) | .number] | first // empty' <<<"$json")" || return 1
  [[ -z "$num" || "$num" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$num"
}

# write_body <index> <file>
write_body() {
  local body note repo="${REPOS[$1]}"
  body="Upstream $(span "$repo") changed since the pin on its docs/upstream page."
  body+=$'\n\n'"Run: $RUN_DATE, $RUN_URL"$'\n'"${DETAIL[$1]}"
  body+=$'\n'"Re-audit the rows named above as docs/conventions/upstream-drift/README.md, \"When a trigger fires\", requires. Moving the pin makes the next run clean, which closes this issue."$'\n'
  if ((${#body} > CAP)); then
    note=$'\n'"Cut at $CAP characters. The full report is in the run's job summary: $RUN_URL"$'\n'
    body="${body:0:$((CAP - ${#note}))}"
    body="${body%$'\n'*}"
    body+="$note"
  fi
  printf '%s' "$body" >"$2"
}

for i in "${!REPOS[@]}"; do
  repo="${REPOS[i]}"
  title="Upstream drift: $repo"
  action=none
  if [[ "${STATE[i]}" != none ]]; then
    if ! num="$(open_issue "$title")"; then
      printf '%s: issue list failed for %s\n' "$SELF" "$repo" >&2
      failed=1
      continue
    fi
    if [[ "${STATE[i]}" == drift ]]; then
      action=create
      [[ -n "$num" ]] && action=edit
    elif [[ -n "$num" ]]; then
      action=close
    fi
  fi
  printf 'action=%s repo=%s\n' "$action" "$repo"
  ((DRY)) && continue
  body_file="$TMPDIR_RUN/body-$i.md"
  case "$action" in
  create)
    write_body "$i" "$body_file"
    gh issue create --title "$title" --body-file "$body_file" >/dev/null || {
      printf '%s: issue create failed for %s\n' "$SELF" "$repo" >&2
      failed=1
    }
    ;;
  edit)
    write_body "$i" "$body_file"
    gh issue edit "$num" --body-file "$body_file" >/dev/null || {
      printf '%s: issue edit failed for %s\n' "$SELF" "$repo" >&2
      failed=1
    }
    ;;
  close)
    gh issue close "$num" --comment "Upstream $(span "$repo") is clean against its pin as of $RUN_DATE ($RUN_URL)." >/dev/null || {
      printf '%s: issue close failed for %s\n' "$SELF" "$repo" >&2
      failed=1
    }
    ;;
  *) ;; # none
  esac
done

exit "$failed"
