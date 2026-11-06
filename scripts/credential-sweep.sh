#!/usr/bin/env bash
# Answer one question: can anyone obtain a credential from an owner's public
# GitHub data? Downloads what a public repository exposes, scans it with
# gitleaks, and reports hits (always redacted) and everything it could not read.
#
#   scripts/credential-sweep.sh [--owner OWNER] [--repo NAME ...]
#                               [--since YYYY-MM-DD] [--out DIR] [--keep]
#                               [--reserve N] [--interval SECONDS]
#
#   --owner    GitHub owner (default melodic-software)
#   --repo     sweep only NAME, which must be public; repeatable. Default:
#              every public repo of OWNER.
#   --since    first day of activity to sweep (default 90 days ago, GitHub's
#              default log and artifact retention)
#   --out      report directory (default .work/credential-sweep/<UTC stamp>)
#   --keep     keep the downloads under DIR/downloads (they hold raw values)
#   --reserve  REST requests left for other work: below N remaining, wait for
#              the hourly reset (default 1500)
#   --interval minimum seconds from one request's start to the next one's,
#              decimals allowed (default 1)
#
# Sources per repository. --since bounds runs, artifacts and comments; releases
# and caches are swept whole.
#   logs         every attempt of every Actions run created since --since,
#                listed one UTC day at a time; a window whose total_count is
#                over the 1,000 results a filtered run list returns is halved
#                until it fits, and a window listed short of its total_count
#                is a gap. A run skipped on its only attempt (no job ran) is
#                counted, not fetched.
#   check-runs   output title, summary and text of each run's check runs, every
#                attempt
#   artifacts    every artifact created since --since, unzipped; one uploaded
#                unzipped (a Docker build record's gzipped tar) is untarred or
#                kept as its one file
#   releases     name and body of every published release, and its assets
#   bot-comments issue, pull request and review comments by Bot accounts
#   bot-reviews  review bodies by Bot accounts on pull requests updated since
#   caches       listed only
#
# Archives over 1 GiB uncompressed are not extracted (a gap), and symlinks in
# an archive are deleted after extraction.
#
# Two kinds of unread data are reported apart. UNREADABLE BY DESIGN is what the
# API serves to nobody: cache contents, job step summaries (no REST endpoint
# serves GITHUB_STEP_SUMMARY), expired artifacts and logs (HTTP 410). It is counted in its own
# section and never moves the exit code. A GAP is something readable that was
# not read: a failed list or download, an unparsable page, a rate-limit stop.
#
# Binaries get a strings(1) -n 8 pass whose output is scanned as text, written
# under downloads/<repo>/strings/ so it never replaces a downloaded file; nested
# archives are read by gitleaks --max-archive-depth.
#
# Read-only: every request is a REST GET, one at a time, each starting at least
# --interval seconds after the one before. Every JSON response's
# x-ratelimit-remaining and x-ratelimit-reset headers are read (downloads
# redirect to storage that sends none); when remaining falls below --reserve,
# the sweep sleeps until the reset, so it never takes the budget other work on
# the same login needs. The first rate-limit error, a secondary rate limit
# included, stops the sweep, which reports it as a gap and sends nothing more.
#
# The scanner is gitleaks at the version the lint-repo `Scan for secrets` step
# installs (melodic-software/ci-workflows gitleaks action, pinned in
# .github/workflows/pr-require-checks.yml), with that version's default config
# (one GET of config/gitleaks.toml at the tag) minus its global path allowlist,
# which skips lockfiles, node_modules/, vendor/, images and office files: in a
# download those can hold a credential like any other file. Rule-level path
# allowlists stay. Every output is redacted: gitleaks runs with --redact, and
# the report keeps only rule, path and line.
#
# Exit: 0 no hits and nothing readable missed; 1 hits; 2 gaps and no hits;
# 3 could not start (usage,
# missing tool, wrong gitleaks version, no repository list).
set -uo pipefail

PROG="credential-sweep.sh"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"
GITLEAKS_PIN="8.30.1"
# The commit tag v8.30.1 names; the default config is read at it, not at the movable tag.
GITLEAKS_CONFIG_COMMIT="83d9cd684c87d95d656c1458ef04895a7f1cbd8e"
PER_PAGE=100
UNPACK_MAX=$((1024 * 1024 * 1024))
# "This endpoint will return up to 1,000 results for each search when using the
# following parameters: actor, branch, check_suite_id, created, ..."
# (docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository)
LIST_CAP=1000

OWNER="melodic-software"
REPOS=()
SINCE=""
OUT=""
KEEP=0
RESERVE=1500
INTERVAL=1
INTERVAL_US=""
LAST_START=""

DL=""
STATE=""
API_ERR=""
STOPPED=""
REQUESTS=0
REMAINING=""
RESET=""
PAUSES=0
PAUSED=0
SKIPPED=0
MAX_TOTAL=""
TOTAL=""
declare -A COUNT=()

die() {
  printf '%s: %s\n' "$PROG" "$*" >&2
  exit 3
}

usage() {
  sed -n '6,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 3
}

cleanup() {
  if ((KEEP == 0)); then
    [[ -z "$DL" ]] || rm -rf "${DL:?}"
    [[ -z "$STATE" ]] || rm -rf "${STATE:?}"
  fi
}

gap() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$STATE/gaps.tsv"; }
by_design() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$STATE/by-design.tsv"; }
bump() { COUNT["$1:$2"]=$((${COUNT["$1:$2"]:-0} + ${3:-1})); }
safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }

# pace: before a request, when the last remaining count read is below RESERVE,
# sleep until its reset. The count is then unknown until the next headers.
pace() {
  local wait
  [[ -n "$REMAINING" && -n "$RESET" ]] && ((REMAINING < RESERVE)) || return 0
  wait=$((RESET - $(date +%s) + 1))
  if ((wait > 0)); then
    printf '%s: %s REST requests left, under the reserve of %s; waiting %ss for the reset\n' \
      "$PROG" "$REMAINING" "$RESERVE" "$wait" >&2
    PAUSES=$((PAUSES + 1))
    PAUSED=$((PAUSED + wait))
    sleep "$wait"
  fi
  REMAINING=""
}

# set_interval <seconds>: sets INTERVAL and INTERVAL_US from a whole or decimal
# number of seconds; returns 1 for anything else.
set_interval() {
  [[ -n "$1" && "$1" =~ ^([0-9]{0,6})(\.([0-9]+))?$ ]] || return 1
  local frac="${BASH_REMATCH[3]}000000"
  INTERVAL="$1"
  INTERVAL_US=$((10#${BASH_REMATCH[1]:-0} * 1000000 + 10#${frac:0:6}))
}

# space: before a request, sleep until INTERVAL has passed since the last
# request started, then record this start. EPOCHREALTIME is microsecond wall
# time, read in-process.
space() {
  local now="${EPOCHREALTIME/[.,]/}" wait
  if [[ -n "$LAST_START" ]] && ((wait = LAST_START + INTERVAL_US - now, wait > 0)); then
    # A wall clock stepped back would ask for more than one interval.
    ((wait <= INTERVAL_US)) || wait=$INTERVAL_US
    sleep "$((wait / 1000000)).$(printf '%06d' $((wait % 1000000)))"
    now="${EPOCHREALTIME/[.,]/}"
  fi
  LAST_START="$now"
}

# read_headers <response> <body>: splits a gh api --include response at the
# first blank line, and sets REMAINING and RESET from the headers it carries.
read_headers() {
  local v
  awk -v h="$STATE/headers" -v b="$2" 'body { print > b; next } /^\r?$/ { body = 1; next } { print > h }' "$1"
  [[ -f "$STATE/headers" ]] || return 0
  v="$(awk -F ': *' 'tolower($1) == "x-ratelimit-remaining" { sub(/\r$/, "", $2); print $2 }' "$STATE/headers")"
  [[ ! "$v" =~ ^[0-9]+$ ]] || REMAINING="$v"
  v="$(awk -F ': *' 'tolower($1) == "x-ratelimit-reset" { sub(/\r$/, "", $2); print $2 }' "$STATE/headers")"
  [[ ! "$v" =~ ^[0-9]+$ ]] || RESET="$v"
  rm -f "$STATE/headers"
}

# api_get <outfile> <path> [gh api args]: one GET of a JSON or text response,
# whose rate-limit headers pace the sweep. api_download: one GET of a file,
# written as served. Each returns 0 ok, 1 error (text in API_ERR), 3
# rate-limited or already stopped.
api_get() { request headers "$@"; }
api_download() { request raw "$@"; }

request() {
  local mode="$1" out="$2" path="$3" rc
  shift 3
  [[ -z "$STOPPED" ]] || return 3
  pace
  space
  REQUESTS=$((REQUESTS + 1))
  [[ -z "$REMAINING" ]] || REMAINING=$((REMAINING - 1))
  if [[ "$mode" == raw ]]; then
    gh api --method GET "$@" "$path" >"$out" 2>"$STATE/err" </dev/null
    rc=$?
  else
    gh api --method GET --include "$@" "$path" >"$STATE/response" 2>"$STATE/err" </dev/null
    rc=$?
    : >"$out"
    read_headers "$STATE/response" "$out"
  fi
  ((rc != 0)) || return 0
  API_ERR="$(tr '\n' ' ' <"$STATE/err" | cut -c1-200)"
  if grep -qiE 'rate limit|HTTP 429|abuse detection' "$STATE/err"; then
    STOPPED="rate limit on GET $path: $API_ERR"
    return 3
  fi
  return 1
}

# fetch_pages <dest.jsonl> <path> <items-jq> [date-field]: every page of a
# list, one JSON item per line. With a date field, stops after a page whose
# items are all older than --since. Sets TOTAL to page 1's total_count, if
# any; when MAX_TOTAL is set and TOTAL exceeds it, returns 4 after page 1.
fetch_pages() {
  local dest="$1" path="$2" items="$3" field="${4:-}" page=1 n rc sep='?'
  local tmp="$STATE/page.json"
  [[ "$path" != *'?'* ]] || sep='&'
  : >"$dest"
  TOTAL=""
  while :; do
    api_get "$tmp" "$path${sep}per_page=$PER_PAGE&page=$page"
    rc=$?
    ((rc == 0)) || return "$rc"
    if ! jq -c "$items" "$tmp" >>"$dest" 2>/dev/null; then
      API_ERR="unparsable response for $path page $page"
      return 1
    fi
    if ((page == 1)); then
      TOTAL="$(jq -r 'if type == "object" then .total_count // "" else "" end' "$tmp")"
      [[ -z "$MAX_TOTAL" || -z "$TOTAL" ]] || ((TOTAL <= MAX_TOTAL)) || return 4
    fi
    # The page's own length, before any select in $items, decides paging.
    n="$(jq 'if type == "array" then length else ([.[] | arrays][0] // [] | length) end' "$tmp")"
    ((n == PER_PAGE)) || return 0
    if [[ -n "$field" ]] &&
      [[ "$(jq --arg s "$SINCE" "[$items | select(.$field >= \$s)] | length" "$tmp")" == 0 ]]; then
      return 0
    fi
    page=$((page + 1))
  done
}

# unpack <zip> <dir>: extract and drop the archive; a failure is a gap. An
# archive over UNPACK_MAX bytes uncompressed is not extracted. Symlinks in the
# archive are deleted, so no later read or write follows one out of the tree.
unpack() {
  local size totals
  totals="$(unzip -Zt "$1" 2>/dev/null)"
  # A run that never started a job (a skipped run) serves an empty archive.
  if [[ "$totals" == "Empty zipfile." ]]; then
    rm -f "$1"
    mkdir -p "$2"
    return 0
  fi
  size="$(awk '{ for (i = 1; i < NF; i++) if ($(i + 1) ~ /^bytes/) { print $i; exit } }' <<<"$totals")"
  if [[ ! "$size" =~ ^[0-9]+$ ]] || ((size > UNPACK_MAX)); then
    API_ERR="archive size unreadable or over $UNPACK_MAX bytes uncompressed (${size:-unknown})"
    rm -f "$1"
    return 1
  fi
  mkdir -p "$2"
  if unzip -q -o "$1" -d "$2" >/dev/null 2>&1; then
    find "$2" -type l -delete
    rm -f "$1"
    return 0
  fi
  API_ERR="archive did not unzip"
  return 1
}

# unpack_artifact <download> <dir>: an artifact uploaded unzipped (a Docker
# build record is a gzipped tar) comes back as its own bytes, not a zip. A zip
# goes to unpack. A gzip is decompressed through a bounded read; that stream,
# or the download itself, is extracted only when it is a plain tar (the ustar
# magic at offset 257), so tar never decompresses anything unbounded. Any other
# file (an xz, bzip2 or zstd tar included) is kept as one file and scanned as
# bytes. The UNPACK_MAX cap applies to the decompressed stream and to the
# extracted files; symlinks are deleted whether or not tar succeeds.
unpack_artifact() {
  local lead size name raw rc
  lead="$(head -c 2 "$1" | od -An -tx1 | tr -d ' \n')"
  raw="$1.raw"
  case "$lead" in
  504b)
    unpack "$@"
    return
    ;;
  '')
    API_ERR="artifact download is empty"
    rm -f "$1"
    return 1
    ;;
  1f8b)
    gzip -dc <"$1" 2>/dev/null | head -c $((UNPACK_MAX + 1)) >"$raw"
    rc="${PIPESTATUS[0]}"
    rm -f "$1"
    ;;
  *)
    mv "$1" "$raw"
    rc=0
    ;;
  esac
  size="$(wc -c <"$raw" | tr -d ' ')"
  if ((size > UNPACK_MAX)); then
    API_ERR="artifact over $UNPACK_MAX bytes uncompressed"
    rm -f "$raw"
    return 1
  fi
  if ((rc != 0)); then
    API_ERR="artifact did not gunzip"
    rm -f "$raw"
    return 1
  fi
  mkdir -p "$2"
  name="$2/$(basename "$2")"
  if [[ "$(tail -c +258 "$raw" | head -c 5)" != ustar ]]; then
    mv "$raw" "$name"
    return 0
  fi
  tar -xf "$raw" -C "$2" >/dev/null 2>&1
  rc=$?
  rm -f "$raw"
  find "$2" -type d -exec chmod u+rwx {} +
  find "$2" -type l -delete
  if ((rc != 0)); then
    API_ERR="artifact tar did not extract"
    rm -rf "${2:?}"
    return 1
  fi
  # A sparse member can declare more than the stream held.
  size="$(find "$2" -type f -exec cat {} + | head -c $((UNPACK_MAX + 1)) | wc -c | tr -d ' ')"
  if ((size > UNPACK_MAX)); then
    API_ERR="artifact over $UNPACK_MAX bytes extracted"
    rm -rf "${2:?}"
    return 1
  fi
  return 0
}

utc() { jq -rn --argjson t "$1" '$t | strftime("%Y-%m-%dT%H:%M:%SZ")'; }

# list_runs <repo> <base> <from> <to>: runs created in [from, to] (epoch
# seconds, inclusive) appended to $STATE/runs.jsonl. A window whose total_count
# is over LIST_CAP is halved until it fits; one that cannot be halved, or that
# lists fewer runs than its total_count, is a gap. Returns 3 on a stop.
list_runs() {
  local r="$1" base="$2" from="$3" to="$4" window rc n mid
  window="$(utc "$from")..$(utc "$to")"
  MAX_TOTAL=$LIST_CAP
  ((to - from >= 1)) || MAX_TOTAL=""
  # Only the fields the sweep reads are kept: a full run object is several KB.
  fetch_pages "$STATE/window.jsonl" "$base/actions/runs?exclude_pull_requests=true&created=$window" \
    '.workflow_runs[] | {id, run_attempt, check_suite_id, conclusion}'
  rc=$?
  MAX_TOTAL=""
  ((rc != 3)) || return 3
  if ((rc == 4)); then
    mid=$((from + (to - from) / 2))
    list_runs "$r" "$base" "$from" "$mid" || return 3
    list_runs "$r" "$base" "$((mid + 1))" "$to"
    return
  fi
  if ((rc != 0)); then
    gap "$r" logs "run list for $window unreadable: $API_ERR"
    return 0
  fi
  cat "$STATE/window.jsonl" >>"$STATE/runs.jsonl"
  n="$(wc -l <"$STATE/window.jsonl")"
  [[ -z "$TOTAL" ]] || ((n >= TOTAL)) ||
    gap "$r" logs "run list for $window: listed $n of total_count $TOTAL"
  return 0
}

sweep_logs_and_checks() {
  local r="$1" base="$2" dl="$3" id attempt suite a rc jobs=0 n day end
  : >"$STATE/runs.jsonl"
  day="$(jq -rn --arg s "$SINCE" '$s | strptime("%Y-%m-%d") | mktime')"
  end="$(date +%s)"
  for (( ; day <= end; day += 86400)); do
    list_runs "$r" "$base" "$day" "$((day + 86399))" || return 3
  done
  while IFS=$'\t' read -r id attempt suite conclusion; do
    bump "$r" runs
    # A skipped run started no job: its log archive is empty and its check
    # runs carry no output, so neither is fetched. The conclusion is the
    # latest attempt's, so a re-run's earlier attempts are still read.
    if [[ "$conclusion" == skipped ]] && ((attempt == 1)); then
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    for ((a = 1; a <= attempt; a++)); do
      api_download "$dl/logs/run-$id-attempt-$a.zip" "$base/actions/runs/$id/attempts/$a/logs"
      rc=$?
      ((rc != 3)) || return 3
      if ((rc != 0)); then
        rm -f "$dl/logs/run-$id-attempt-$a.zip"
        if [[ "$API_ERR" == *'HTTP 410'* ]]; then
          by_design "$r" logs "run $id attempt $a: logs expired or deleted (HTTP 410)"
        else
          gap "$r" logs "run $id attempt $a: $API_ERR"
        fi
      elif unpack "$dl/logs/run-$id-attempt-$a.zip" "$dl/logs/run-$id-attempt-$a"; then
        bump "$r" logs
      else
        gap "$r" logs "run $id attempt $a: $API_ERR"
      fi
    done
    fetch_pages "$STATE/checks.jsonl" "$base/check-suites/$suite/check-runs?filter=all" '.check_runs[]'
    rc=$?
    ((rc != 3)) || return 3
    if ((rc != 0)); then
      gap "$r" check-runs "run $id suite $suite: $API_ERR"
      continue
    fi
    n="$(wc -l <"$STATE/checks.jsonl")"
    jobs=$((jobs + n))
    bump "$r" check-runs "$n"
    jq -r '"check-run \(.id) \(.name)\ntitle: \(.output.title // "")\nsummary: \(.output.summary // "")\ntext: \(.output.text // "")\n"' \
      "$STATE/checks.jsonl" >"$dl/check-runs/run-$id.txt"
  done < <(jq -r '[.id, (.run_attempt // 1), .check_suite_id, (.conclusion // "")] | @tsv' "$STATE/runs.jsonl" |
    awk -F '\t' '!seen[$1]++')
  ((jobs == 0)) || by_design "$r" step-summaries "$jobs jobs: no REST endpoint serves GITHUB_STEP_SUMMARY"
  return 0
}

sweep_artifacts() {
  local r="$1" base="$2" dl="$3" id name expired rc dir
  fetch_pages "$STATE/artifacts.jsonl" "$base/actions/artifacts" '.artifacts[]' created_at
  rc=$?
  ((rc != 3)) || return 3
  if ((rc != 0)); then
    gap "$r" artifacts "artifact list unreadable: $API_ERR"
    return 0
  fi
  while IFS=$'\t' read -r id name expired; do
    if [[ "$expired" == true ]]; then
      by_design "$r" artifacts "artifact $id ($name): expired, contents gone"
      continue
    fi
    dir="$dl/artifacts/$id-$(safe_name "$name")"
    api_download "$dir.zip" "$base/actions/artifacts/$id/zip"
    rc=$?
    ((rc != 3)) || return 3
    if ((rc != 0)); then
      rm -f "$dir.zip"
      gap "$r" artifacts "artifact $id ($name): $API_ERR"
    elif unpack_artifact "$dir.zip" "$dir"; then
      bump "$r" artifacts
    else
      gap "$r" artifacts "artifact $id ($name): $API_ERR"
    fi
  done < <(jq -r --arg s "$SINCE" 'select(.created_at >= $s) | [.id, .name, .expired] | @tsv' "$STATE/artifacts.jsonl")
  return 0
}

sweep_releases() {
  local r="$1" base="$2" dl="$3" rid aid name rc file
  fetch_pages "$STATE/releases.jsonl" "$base/releases" '.[] | select(.draft == false)'
  rc=$?
  ((rc != 3)) || return 3
  if ((rc != 0)); then
    gap "$r" releases "release list unreadable: $API_ERR"
    return 0
  fi
  while IFS= read -r rid; do
    jq -r --argjson id "$rid" 'select(.id == $id) | "release \(.id) \(.tag_name)\nname: \(.name // "")\n\(.body // "")"' \
      "$STATE/releases.jsonl" >"$dl/releases/$rid.md"
    bump "$r" releases
  done < <(jq -r '.id' "$STATE/releases.jsonl")
  while IFS=$'\t' read -r rid aid name; do
    file="$dl/release-assets/$rid-$aid-$(safe_name "$name")"
    api_download "$file" "$base/releases/assets/$aid" -H 'Accept: application/octet-stream'
    rc=$?
    ((rc != 3)) || return 3
    if ((rc != 0)); then
      rm -f "$file"
      gap "$r" release-assets "asset $aid ($name): $API_ERR"
    else
      bump "$r" release-assets
    fi
  done < <(jq -r '.id as $r | .assets[]? | [$r, .id, .name] | @tsv' "$STATE/releases.jsonl")
  return 0
}

sweep_comments() {
  local r="$1" base="$2" dl="$3" kind rc
  for kind in issues pulls; do
    fetch_pages "$STATE/comments.jsonl" "$base/$kind/comments?since=${SINCE}T00:00:00Z" '.[] | select(.user.type == "Bot")'
    rc=$?
    ((rc != 3)) || return 3
    if ((rc != 0)); then
      gap "$r" bot-comments "$kind comments unreadable: $API_ERR"
      continue
    fi
    jq -r '"comment \(.id) by \(.user.login) \(.html_url)\n\(.body // "")\n"' \
      "$STATE/comments.jsonl" >"$dl/bot-comments/$kind.txt"
    bump "$r" bot-comments "$(wc -l <"$STATE/comments.jsonl")"
  done
  sweep_reviews "$@"
}

# sweep_reviews: review bodies by Bot accounts on every pull request updated
# since --since; no repository-wide endpoint lists reviews.
sweep_reviews() {
  local r="$1" base="$2" dl="$3" pr rc
  fetch_pages "$STATE/pulls.jsonl" "$base/pulls?state=all&sort=updated&direction=desc" '.[]' updated_at
  rc=$?
  ((rc != 3)) || return 3
  if ((rc != 0)); then
    gap "$r" bot-reviews "pull request list unreadable: $API_ERR"
    return 0
  fi
  : >"$dl/bot-comments/reviews.txt"
  while IFS= read -r pr; do
    fetch_pages "$STATE/reviews.jsonl" "$base/pulls/$pr/reviews" '.[] | select(.user.type == "Bot")'
    rc=$?
    ((rc != 3)) || return 3
    if ((rc != 0)); then
      gap "$r" bot-reviews "pull request $pr reviews unreadable: $API_ERR"
      continue
    fi
    jq -r '"review \(.id) by \(.user.login) \(.html_url)\n\(.body // "")\n"' \
      "$STATE/reviews.jsonl" >>"$dl/bot-comments/reviews.txt"
    bump "$r" bot-reviews "$(wc -l <"$STATE/reviews.jsonl")"
  done < <(jq -r --arg s "$SINCE" 'select(.updated_at >= $s) | .number' "$STATE/pulls.jsonl")
  return 0
}

# check_public <repo>: a --repo name must be a public repository of OWNER.
check_public() {
  local tmp="$STATE/repo.json"
  api_get "$tmp" "repos/$OWNER/$1" || die "cannot read repos/$OWNER/$1: ${STOPPED:-$API_ERR}"
  [[ "$(jq -r '.private' "$tmp")" == false ]] || die "$OWNER/$1 is not public; this sweep reads public data only"
}

sweep_caches() {
  local r="$1" base="$2" rc n
  fetch_pages "$STATE/caches.jsonl" "$base/actions/caches" '.actions_caches[]'
  rc=$?
  ((rc != 3)) || return 3
  if ((rc != 0)); then
    gap "$r" caches "cache list unreadable: $API_ERR"
    return 0
  fi
  n="$(wc -l <"$STATE/caches.jsonl")"
  bump "$r" caches "$n"
  ((n == 0)) || by_design "$r" caches "$n entries listed; the API serves no cache contents"
  return 0
}

sweep_repo() {
  local r="$1" base="repos/$OWNER/$1" dl="$DL/$1" step
  mkdir -p "$dl/logs" "$dl/check-runs" "$dl/artifacts" "$dl/releases" "$dl/release-assets" "$dl/bot-comments"
  for step in sweep_logs_and_checks sweep_artifacts sweep_releases sweep_comments sweep_caches; do
    "$step" "$r" "$base" "$dl" || return 3
  done
  return 0
}

list_public_repos() {
  local rc
  fetch_pages "$STATE/repos.jsonl" "orgs/$OWNER/repos?type=public" '.[] | select(.private == false) | .name'
  rc=$?
  if ((rc == 1)); then
    fetch_pages "$STATE/repos.jsonl" "users/$OWNER/repos?type=owner" '.[] | select(.private == false) | .name'
    rc=$?
  fi
  ((rc == 0)) || die "cannot list the public repositories of $OWNER: ${STOPPED:-$API_ERR}"
  mapfile -t REPOS < <(jq -r '.' "$STATE/repos.jsonl")
}

# strings_pass: a text copy of every non-empty binary under <repo>/strings/,
# a directory the sweep creates and no download writes into.
strings_pass() {
  local d f out
  for d in "$DL"/*/; do
    d="${d%/}"
    while IFS= read -r -d '' f; do
      LC_ALL=C grep -qI . "$f" && continue
      out="$d/strings/${f#"$d/"}.strings.txt"
      mkdir -p "${out%/*}"
      strings -n 8 "$f" >"$out"
    done < <(find "$d" -path "$d/strings" -prune -o -type f -size +0 -print0)
  done
}

# fetch_config: the pinned default config without its global path allowlist,
# into $STATE/sweep.toml. A [allowlist] or [[allowlists]] table loses every
# paths key; [[rules.allowlists]] tables are kept whole. Dies when the file is
# unreadable or holds no rules, when a global paths key survives the strip, or
# when the strip lost a rule.
fetch_config() {
  local raw="$STATE/default.toml" out="$STATE/sweep.toml"
  api_get "$raw" "repos/gitleaks/gitleaks/contents/config/gitleaks.toml?ref=$GITLEAKS_CONFIG_COMMIT" \
    -H 'Accept: application/vnd.github.raw' ||
    die "cannot read the gitleaks $GITLEAKS_PIN default config: ${STOPPED:-$API_ERR}"
  grep -q '^\[\[rules\]\]' "$raw" || die "the gitleaks $GITLEAKS_PIN default config holds no rules"
  # A header resets the state; comments are cut from header lines only, since
  # content lines hold regexes with # inside.
  awk '
    /^[[:space:]]*\[/ {
      h = $0; sub(/#.*$/, "", h); gsub(/[[:space:]]/, "", h)
      global = (h == "[allowlist]" || h == "[[allowlists]]"); skip = 0
    }
    skip { if ($0 ~ /^[[:space:]]*\]/ || $0 ~ /\][[:space:]]*$/) skip = 0; next }
    global && /^[[:space:]]*paths[[:space:]]*=/ {
      v = $0; sub(/^[^=]*=[[:space:]]*/, "", v)
      if (v ~ /^\[/ && v !~ /\][[:space:]]*(#.*)?$/) skip = 1
      next
    }
    { print }
  ' "$raw" >"$out"
  ! global_paths "$out" ||
    die "could not strip the global path allowlist from the gitleaks $GITLEAKS_PIN default config: a [allowlist] or [[allowlists]] table still has a paths key"
  [[ "$(grep -c '^\[\[rules\]\]' "$out")" == "$(grep -c '^\[\[rules\]\]' "$raw")" ]] ||
    die "stripping the global path allowlist from the gitleaks $GITLEAKS_PIN default config lost a [[rules]] table"
}

# global_paths <toml>: true when a global allowlist table, matched more loosely
# than the strip does (spaced or quoted names and keys, a dotted
# allowlist.paths before any table), still sets paths.
global_paths() {
  awk '
    /^[[:space:]]*\[/ {
      h = $0; sub(/#.*$/, "", h); gsub(/[[:space:]"\047]/, "", h)
      table = 1; global = (h == "[allowlist]" || h == "[[allowlists]]")
    }
    !table && /^[[:space:]]*["\047]?allowlists?["\047]?[[:space:]]*\.[[:space:]]*["\047]?paths["\047]?[[:space:]]*=/ { found = 1 }
    global && /^[[:space:]]*["\047]?paths["\047]?[[:space:]]*=/ { found = 1 }
    END { exit !found }
  ' "$1"
}

# scan: gitleaks over the whole download tree; writes $OUT/findings.json with
# rule, path and line only. Returns 0 scanned, 1 scanner failure.
scan() {
  local rc
  mkdir -p "$STATE/no-ignore"
  gitleaks dir --no-banner --no-color --log-level error --redact --ignore-gitleaks-allow \
    --max-archive-depth 8 --exit-code 9 -c "$STATE/sweep.toml" -i "$STATE/no-ignore" \
    -f json -r "$STATE/gitleaks.json" "$DL" >"$STATE/gitleaks.log" 2>&1
  rc=$?
  if ((rc != 0 && rc != 9)) || [[ ! -f "$STATE/gitleaks.json" ]]; then
    return 1
  fi
  jq --arg p "$DL/" '[.[] | {rule: .RuleID, path: (.File | ltrimstr($p)), line: .StartLine}] | sort_by(.path, .line)' \
    "$STATE/gitleaks.json" >"$OUT/findings.json"
}

report() {
  local r src hits gaps
  local sources=(runs logs check-runs artifacts releases release-assets bot-comments bot-reviews caches)
  hits="$(jq length "$OUT/findings.json")"
  gaps="$(wc -l <"$STATE/gaps.tsv")"
  {
    printf '# Credential sweep: %s since %s\n\n' "$OWNER" "$SINCE"
    printf 'Scanner: gitleaks %s, default config without its global path allowlist, redacted. Binaries: strings(1) -n 8 pass, scanned as text (<repo>/strings/). Nested archives: gitleaks --max-archive-depth 8.\n' \
      "$GITLEAKS_PIN"
    printf 'API requests: %d (REST GET only). Reserve: %d; waited for the reset %d times, %ds. Interval: %ss between request starts.\n' \
      "$REQUESTS" "$RESERVE" "$PAUSES" "$PAUSED" "$INTERVAL"
    printf 'skipped runs (no job ran): %d; their logs and check runs are not fetched.\n\n## Swept\n\n' "$SKIPPED"
    printf '| repo |'
    printf ' %s |' "${sources[@]}" hits
    printf '\n|---|'
    printf -- '---|%.0s' "${sources[@]}" hits
    printf '\n'
    for r in "${REPOS[@]}"; do
      printf '| %s |' "$r"
      for src in "${sources[@]}"; do printf ' %s |' "${COUNT["$r:$src"]:-0}"; done
      printf ' %s |\n' "$(jq --arg r "$r/" '[.[] | select(.path | startswith($r))] | length' "$OUT/findings.json")"
    done
    printf '\n## Hits (%d)\n\n' "$hits"
    if ((hits == 0)); then
      printf 'None\n'
    else
      printf '| rule | location | line |\n|---|---|---|\n'
      jq -r '.[] | "| \(.rule) | \(.path) | \(.line) |"' "$OUT/findings.json"
    fi
    printf '\n## GAPS (%d)\n\n' "$gaps"
    if ((gaps == 0)); then
      printf 'None\n'
    else
      awk -F '\t' '{ printf "- %s: %s: %s\n", $1, $2, $3 }' "$STATE/gaps.tsv"
    fi
    printf '\n## Unreadable by design (%d)\n\nThe API serves these to nobody; they do not change the exit code.\n\n' \
      "$(wc -l <"$STATE/by-design.tsv")"
    if [[ -s "$STATE/by-design.tsv" ]]; then
      awk -F '\t' '{ printf "- %s: %s: %s\n", $1, $2, $3 }' "$STATE/by-design.tsv"
    else
      printf 'None\n'
    fi
  } | tr -d '\000-\010\013-\037\177' >"$OUT/summary.md"
  cat "$OUT/summary.md"
  printf '\nReport: %s\n' "$OUT/summary.md"
  if ((hits > 0)); then
    return 1
  elif ((gaps > 0)); then
    return 2
  fi
  return 0
}

main() {
  local i r tool
  while (($# > 0)); do
    case "$1" in
      --keep)
        KEEP=1
        shift
        continue
        ;;
      --owner | --repo | --since | --out | --reserve | --interval) [[ -n "${2:-}" ]] || usage ;;
      *) usage ;;
    esac
    case "$1" in
      --owner) OWNER="$2" ;;
      --repo) REPOS+=("$2") ;;
      --since) SINCE="$2" ;;
      --reserve) RESERVE="$2" ;;
      --interval) INTERVAL="$2" ;;
      *) OUT="$2" ;;
    esac
    shift 2
  done
  [[ "$RESERVE" =~ ^[0-9]+$ ]] || die "--reserve must be a whole number, got '$RESERVE'"
  set_interval "$INTERVAL" || die "usage: --interval SECONDS takes a number such as 1 or 1.5, got '$INTERVAL'"
  [[ -n "${EPOCHREALTIME:-}" ]] || die "bash 5 or later is required (EPOCHREALTIME spaces the requests)"
  for tool in gh jq unzip strings gitleaks; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is not on PATH"
  done
  [[ -n "$SINCE" ]] || SINCE="$(jq -rn 'now - 90 * 86400 | strftime("%Y-%m-%d")')"
  # A real calendar day survives the parse-and-format round trip unchanged.
  [[ "$(jq -rn --arg d "$SINCE" '$d | strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")' 2>/dev/null)" == "$SINCE" ]] ||
    die "--since must be a YYYY-MM-DD date, got '$SINCE'"
  [[ "$(gitleaks version 2>/dev/null)" == "$GITLEAKS_PIN" ]] ||
    die "gitleaks $GITLEAKS_PIN required (the lint-repo pin); found '$(gitleaks version 2>&1 | head -n 1)'"

  [[ -n "$OUT" ]] || OUT="$ROOT/.work/credential-sweep/$(date -u +%Y%m%dT%H%M%SZ)"
  [[ ! -e "$OUT/downloads" ]] || die "$OUT/downloads already exists; pick another --out"
  DL="$OUT/downloads"
  STATE="$OUT/state"
  mkdir -p "$DL" "$STATE" || die "cannot create $OUT"
  : >"$STATE/gaps.tsv"
  : >"$STATE/by-design.tsv"
  trap cleanup EXIT

  if ((${#REPOS[@]} > 0)); then
    for r in "${REPOS[@]}"; do check_public "$r"; done
  else
    list_public_repos
  fi
  fetch_config
  for ((i = 0; i < ${#REPOS[@]}; i++)); do
    r="${REPOS[i]}"
    if [[ -n "$STOPPED" ]]; then
      gap "$r" all "not swept: the sweep stopped on a rate limit"
      continue
    fi
    printf '%s: sweeping %s/%s\n' "$PROG" "$OWNER" "$r" >&2
    sweep_repo "$r" || gap "$r" all "stopped mid-repo: $STOPPED; this source and every later one unread"
  done

  printf '%s: scanning %s\n' "$PROG" "$DL" >&2
  strings_pass
  if ! scan; then
    printf '[]\n' >"$OUT/findings.json"
    gap all scanner "gitleaks failed; nothing was scanned: $(tail -n 3 "$STATE/gitleaks.log" | tr '\n' ' ')"
  fi
  report
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
