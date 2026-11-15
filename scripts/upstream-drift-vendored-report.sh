#!/usr/bin/env bash
# Run each vendored skill's drift check and write one report `page` line per
# row, in the form scripts/upstream-drift-issues.sh reads.
#
#   scripts/upstream-drift-vendored-report.sh --output <file> --broken-contract <file>
#       [--row-timeout <seconds>] [--table <file>]
#   scripts/upstream-drift-vendored-report.sh --list | --help
#
# Each row is `<id>|<check script>|<argument>`: the id is the upstream's
# `<owner>/<repo>`, else `<plugin>/<skill>`; the script path is relative to the
# repository root. ROWS below is the shipped table; --table reads one from a
# file instead (blank and `#` lines skipped). --list prints `<id> <path>` per
# shipped row.
#
# Every row's check runs from the repository root with GH_TOKEN and
# GITHUB_TOKEN removed, under `timeout` (--row-timeout, default 120 seconds).
# Its exit code maps to the page status, under the drift-check contract every
# check script shares:
#   0 clean, 1 drift, 2 untracked with a ::warning,
#   a timeout untracked with a ::warning,
#   any other code untracked with an ::error, and the row id appended to the
#   --broken-contract file.
# Every line reports `pin=unknown head=unknown`: a vendored skill has no git
# pin. The script's stdout and stderr go only to $GITHUB_STEP_SUMMARY (nowhere
# when it is unset), never to this script's own output, so a check's output
# cannot issue a workflow command. This script prints only its annotations.
#
# Exit: 0 every row was emitted, 2 usage, a malformed or empty table, or a
# write that failed. It never exits 1. On 2 neither file is written, and a
# file already at --output is removed, so a partial report never reaches the
# filer, whose close-unreported sweep would close the missing rows' issues.
set -uo pipefail
export LC_ALL=C

SELF="upstream-drift-vendored-report"
REPO_ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)" || exit 2
CAP=60000

ROWS=(
  "playwright/playwright|plugins/playwright/skills/playwright/scripts/update.sh|--check"
  "firecrawl/update|plugins/firecrawl/skills/update/scripts/update.sh|--check"
  "playbooks/boris|plugins/playbooks/skills/boris/scripts/update.sh|--check"
  "playbooks/skill-authoring|plugins/playbooks/skills/skill-authoring/scripts/update.sh|--check"
  "Dometrain/mcp|plugins/dometrain/skills/update/scripts/update.sh|--check"
  "upstash/context7|plugins/context7/skills/lookup/scripts/update.sh|"
  "vojtaholik/good-css|plugins/user-interface/scripts/check-good-css-drift.sh|--check"
)

usage() {
  printf 'usage: %s --output <file> --broken-contract <file> [--row-timeout <seconds>] [--table <file>] | --list | --help\n' "${0##*/}"
}

OUTPUT="" BROKEN=""
die() {
  printf '%s: %s\n' "$SELF" "$*" >&2
  [[ -z "$OUTPUT" ]] || rm -f -- "$OUTPUT"
  [[ -z "$BROKEN" ]] || rm -f -- "$BROKEN"
  exit 2
}

TABLE="" TIMEOUT=120 LIST=0
while (($# > 0)); do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --list) LIST=1 ;;
  --output | --broken-contract | --row-timeout | --table)
    (($# > 1)) || {
      usage >&2
      exit 2
    }
    case "$1" in
    --output) OUTPUT="$2" ;;
    --broken-contract) BROKEN="$2" ;;
    --row-timeout) TIMEOUT="$2" ;;
    *) TABLE="$2" ;;
    esac
    shift
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if ((LIST)); then
  for row in "${ROWS[@]}"; do
    IFS='|' read -r id path _ <<<"$row"
    printf '%s %s\n' "$id" "$path"
  done
  exit 0
fi

[[ -n "$OUTPUT" && -n "$BROKEN" ]] || {
  usage >&2
  exit 2
}
rm -f -- "$OUTPUT" "$BROKEN"
[[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]] || die "--row-timeout takes a whole number of seconds above 0"
command -v timeout >/dev/null 2>&1 || die "timeout is required"

if [[ -n "$TABLE" ]]; then
  [[ -f "$TABLE" && -r "$TABLE" ]] || die "cannot read table: $TABLE"
  ROWS=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] || ROWS+=("$line")
  done <"$TABLE"
fi
((${#ROWS[@]} > 0)) || die "the table has no rows"

# The whole table is checked before any row runs.
for row in "${ROWS[@]}"; do
  IFS='|' read -r id path _ <<<"$row"
  [[ "$id" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "malformed row id: $row"
  [[ -n "$path" && "$path" != -* ]] || die "malformed row path: $row"
done

TMPDIR_RUN="$(mktemp -d)" || die "mktemp failed"
trap 'rm -rf "$TMPDIR_RUN"' EXIT
report="" broken=""

for row in "${ROWS[@]}"; do
  IFS='|' read -r id path arg <<<"$row"
  read -ra args <<<"$arg"
  capture="$TMPDIR_RUN/capture"
  start=$SECONDS
  (cd "$REPO_ROOT" && exec timeout -k 10 "$TIMEOUT" env -u GH_TOKEN -u GITHUB_TOKEN bash "$path" "${args[@]}") \
    >"$capture" 2>&1 </dev/null
  code=$?
  case "$code" in
  0) status=clean ;;
  1) status=drift ;;
  2)
    status=untracked
    printf '::warning title=Drift unverifiable::%s could not be checked (prerequisite, network or usage failure, exit 2).\n' "$id"
    ;;
  *)
    status=untracked
    if ((code == 124 || code == 137)) && ((SECONDS - start >= TIMEOUT)); then
      printf '::warning title=Drift check timed out::%s ran past %s seconds and was stopped.\n' "$id" "$TIMEOUT"
    else
      printf '::error title=Drift check broke its contract::%s exited %s, outside the 0/1/2 drift-check contract.\n' "$id" "$code"
      broken+="$id"$'\n'
    fi
    ;;
  esac
  report+="page repo=$id pin=unknown head=unknown status=$status path=$path"$'\n'
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      # shellcheck disable=SC2016  # the backticks are the literal span delimiters
      printf '### %s\n\nExit code %s. Script: `%s`\n\n~~~~text\n' "$id" "$code" "$path"
      head -c "$CAP" "$capture"
      printf '\n~~~~\n\n'
    } >>"$GITHUB_STEP_SUMMARY"
  fi
done

printf '%s' "$broken" >"$BROKEN" || die "cannot write $BROKEN"
printf '%s' "$report" >"$OUTPUT" || die "cannot write $OUTPUT"
exit 0
