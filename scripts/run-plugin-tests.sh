#!/usr/bin/env bash
# Run every shell test suite in the repository and fail if any fails: the
# plugin contract tests (plugins/**/*.test.sh), the repo-local hook tests
# (.claude/hooks/*.test.sh), and the suites of the repository's own scripts and
# shared libraries (scripts/**/*.test.sh, lib/**/*.test.sh). The repo-local
# hooks are tracked policy with the same test conventions as plugin hooks, and
# a gate's self-test is a suite like any other: CI reaches it through the
# affected-suite selector, not through a step of its own.
#
#   scripts/run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR] [--shard I/N]
#                               [--suites-from FILE] [--budget SECONDS]
#                               [--timings FILE] [SUITE ...]
#   scripts/run-plugin-tests.sh --list [--root DIR]
#
# Each test is self-contained and cwd-independent; an individual test SKIPs
# (exit 0) when an optional tool it needs (shellcheck, shfmt, ...) is absent, so
# this runner gates on real failures without requiring every tool to be present.
#
# Skips are never silent: the summary names every suite that skipped and why,
# so "exit 0 with skips" reads differently from "all green" (a suite whose
# only coverage skipped would be indistinguishable from a pass).
# --strict-skips turns any optional SKIP into a failure, for callers that have
# provisioned the full toolchain and want a skip to mean the environment
# regressed rather than that a tool is optional.
#
# PARALLELISM. --jobs N (default 1, or $PLUGIN_TEST_JOBS) runs up to N suites
# at once. The suites are spawn-bound: on a 4-vCPU Linux runner four at a time
# is the shape that pays, while on Windows Git Bash a parallel run measured
# sublinear (the box saturates on process creation; see the foot of
# scripts/affected-tests.sh), which is why the default stays 1 and CI passes the
# count explicitly. The suites named in scripts/run-plugin-tests-serial.txt
# assert wall-clock ceilings or drive concurrency probes of their own and fail
# spuriously under load, so they run one at a time, before the parallel group,
# and never overlap anything. An entry there that matches no discovered suite
# is an error rather than an ignored line: an allowlist must not outlive what
# it excuses. The parallel group starts longest first by
# scripts/suite-seconds.txt ($PLUGIN_TEST_SECONDS_LIST overrides it), so a long
# suite never starts late and outlasts the rest of its leg; a suite the file
# does not list counts 0 and keeps its sorted place after the listed ones.
#
# BUDGET. --budget SECONDS is the wall clock the whole run aims to finish in,
# for the local affected-only run (scripts/check-affected.sh --tests). A run
# over it reports the overrun and its three slowest suites, and does not fail.
# Each suite gets a share, and a suite that takes longer than its share fails
# by name, unless PLUGIN_TEST_SHARE_WARN_ONLY=1 (below): the share is its scripts/suite-seconds.txt median times
# $PLUGIN_TEST_SHARE_MARGIN (default 3), and never less than
# $PLUGIN_TEST_SHARE_DEFAULT seconds (default 30), the share of a suite the file
# does not list. The medians are CI runner measurements, so the margin covers a
# slower host and a loaded job pool. Each selected suite the file does not list
# is named on stderr with the default share it gets. With
# PLUGIN_TEST_SHARE_WARN_ONLY=1, which scripts/check-affected.sh sets for the
# local gate, a suite over its share is a warning instead, so a suite that
# passes on a loaded host does not fail the run; a suite that fails still does.
# Without --budget no suite is timed against a share, which is how CI runs.
#
# SUITE BUDGET. On GitHub Actions (GITHUB_ACTIONS=true) every suite is timed
# against a per-suite threshold and ceiling: over the threshold it prints
# `SLOW:` and a warning annotation and the run still passes; over the ceiling
# it fails by name. PLUGIN_TEST_SUITE_BUDGET=1 turns the check on anywhere, 0
# off. The numbers and their basis are in README.md "Per-suite time budget in
# CI"; PLUGIN_TEST_SUITE_WARN and PLUGIN_TEST_SUITE_CEILING override them. A
# suite with a row in scripts/suite-budget-exceptions.txt
# ($PLUGIN_TEST_SUITE_EXCEPTIONS overrides it) has that row's ceiling instead;
# an entry there gets the serial list's stale guard.
#
# SHARDING. --shard I/N keeps leg I of N of the sorted discovered suites, by
# index modulo N, with scripts/affected-tests.sh's semantics: the union of legs
# 0..N-1 is the whole corpus and no two legs share a suite, so N runners run it
# once between them. The allowlist's stale guard still reads the full discovery,
# each leg runs its own serial subset first, and a leg that draws nothing exits 0.
#
# Output stays readable under parallelism. Every suite's output is captured to
# a file and replayed as one block under a lock (`=== path ===`, the suite's own
# lines, `PASS:` or `FAIL:`, then `TIME: path <seconds>s`), so blocks from
# concurrent suites never interleave and the per-suite markers that CI log
# tooling reads survive. The block is printed the moment its suite finishes, so
# progress stays visible. The TIME line prints on every run, with or without
# --budget, so a CI log shows each suite's wall seconds.
#
# ADVISORY SUITES. With PLUGIN_TEST_ADVISORY=1 a failing suite named in
# scripts/run-plugin-tests-advisory.txt prints a ::warning:: and its FAIL block
# but does not fail the run. CI sets the variable only for runs on main, so a
# pull request or merge group still fails on it. Without the variable the list
# changes nothing. Its entries get the serial list's stale guard. The warning
# carries a per-run nonce printed before any suite block (`Advisory nonce:`).
#
# --list prints the discovered corpus, one repo-relative path per line, and
# runs nothing. scripts/selection-audit.sh reads it to learn which suites the
# full-corpus fallback runs.
#
# --root DIR discovers suites under DIR instead of the repository (test
# injection for this runner's own suite, scripts/run-plugin-tests.test.sh).
#
# --suites-from FILE runs exactly the newline-delimited suite paths in FILE
# instead of the discovered corpus. This is how scripts/affected-tests.sh hands
# its SELECTION here rather than carrying a second parallel runner of its own:
# the worker, the print lock, the summary and the serial allowlist are this
# file's, and there is one place where a suite is spawned concurrently. The
# allowlist's stale guard still reads the FULL discovery, exactly as it does
# under --shard, so a serial entry that the selection did not draw is still
# matched. An empty file is not an error -- "this selection had nothing to
# run" is a real answer. A SUITE argument is a repo-relative suite path that
# joins that selection, so `run-plugin-tests.sh <suite>` runs that suite alone.
#
# TIMINGS. --timings FILE writes one tab-separated row per suite that reported,
# in corpus order, once every suite has finished: the suite path, its wall
# seconds (the number its TIME line prints) and its exit code. FILE is
# overwritten. Linux and Git Bash write the same format, and the baseline built
# from it is docs/test-wall-clock-baseline.md. Without the flag
# nothing is written and nothing else changes.
set -uo pipefail

# Fixture isolation. `-C` only changes directory, while an exported
# ABSOLUTE GIT_DIR overrides repository DISCOVERY, and `git config`'s default
# --local scope follows whatever gitdir that resolves to. A suite spawned with
# those inherited writes its throwaway fixture identity into the CALLER's
# .git/config — shared by every worktree of the clone — instead of into its
# fixture. What exported them does not matter, so this runner clears them
# unconditionally and isolates every suite it spawns, whatever idiom that suite
# uses internally.
#
# GIT_CONFIG is cleared here too and is a DISTINCT path rather than another
# spelling of the same one: it replaces the file the `git config` subcommand
# reads and writes, so a fixture identity write follows it regardless of -C, of
# GIT_DIR, and of the working directory.
#
# CLAUDE_PLUGIN_DATA is cleared with them. A Bash-run caller can inherit
# another plugin's value, and a hook suite would then write its digest or
# skip-notice into that directory. A suite that needs a data dir sets its own.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG CLAUDE_PLUGIN_DATA

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$script_dir/${BASH_SOURCE[0]##*/}"
# shellcheck source=lib/test-git-env.sh
. "$script_dir/lib/test-git-env.sh"
SERIAL_LIST="${PLUGIN_TEST_SERIAL_LIST:-$script_dir/run-plugin-tests-serial.txt}"
SECONDS_LIST="${PLUGIN_TEST_SECONDS_LIST:-$script_dir/suite-seconds.txt}"
ADVISORY_LIST="${PLUGIN_TEST_ADVISORY_LIST:-$script_dir/run-plugin-tests-advisory.txt}"
EXCEPTIONS_LIST="${PLUGIN_TEST_SUITE_EXCEPTIONS:-$script_dir/suite-budget-exceptions.txt}"

usage() {
  echo "usage: run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR] [--shard I/N] [--suites-from FILE] [--budget SECONDS] [--timings FILE] [SUITE ...] | --list [--root DIR]" >&2
  exit 2
}

# parse_shard <spec>: accept exactly `<i>/<n>` with n >= 1 and 0 <= i < n,
# mirroring scripts/affected-tests.sh. The default is 0/1 rather than unset, so
# an explicit `--shard ""` (an environment variable that expanded to nothing)
# is rejected instead of silently running every suite on every leg.
parse_shard() {
  local spec="$1" i n
  [[ "$spec" =~ ^[0-9]+/[0-9]+$ ]] || return 1
  i=$((10#${spec%%/*}))
  n=$((10#${spec##*/}))
  ((n >= 1 && i < n)) || return 1
  shard_index="$i"
  shard_total="$n"
}

# --worker <NNNNNN:suite>: internal. Runs ONE suite with its output captured
# under $PLUGIN_TEST_LOG_DIR, records its exit status and wall seconds beside
# the capture, then prints the whole block under the print lock. Reached only from the dispatch
# below; it exits 0 regardless of the suite's result so xargs never stops
# early, and the summary reads the recorded status instead.
#
# The capture is keyed on the suite's INDEX, not on its path. A path-derived
# key (slashes rewritten to a separator) collides whenever a path segment
# already contains that separator: plugins/foo__bar/baz.test.sh and
# plugins/foo/bar__baz.test.sh flatten to the same name, and two suites in one
# parallel batch would then overwrite each other's capture and exit status.
# The index is unique by construction, so no path shape can collide. It is
# fixed-width and colon-terminated, which also keeps a path containing a colon
# from being split at the wrong separator.
if [[ "${1:-}" == "--worker" ]]; then
  keyed="${2:?--worker needs an indexed suite path}"
  key="${keyed%%:*}"
  suite="${keyed#*:}"
  log_dir="${PLUGIN_TEST_LOG_DIR:?--worker needs PLUGIN_TEST_LOG_DIR}"
  log="$log_dir/$key"
  rc=0
  test_git_env::isolate "$log.gitconfig" || exit 2
  start=$SECONDS
  bash "$suite" >"$log.out" 2>&1 || rc=$?
  secs=$((SECONDS - start))
  printf '%s\n' "$secs" >"$log.secs"
  printf '%s\n' "$rc" >"$log.rc"
  # noclobber opens the lock with O_EXCL inside bash itself. `mkdir` is not a
  # safe lock everywhere: uutils mkdir (Ubuntu 25.10+) lets two racers both
  # succeed.
  until (set -o noclobber && : >"$log_dir/.print-lock") 2>/dev/null; do sleep 0.02; done
  echo "=== $suite ==="
  cat "$log.out"
  if ((rc == 0)); then
    echo "PASS: $suite"
  else
    echo "FAIL: $suite" >&2
  fi
  echo "TIME: $suite ${secs}s"
  rm -f "$log_dir/.print-lock"
  exit 0
fi

strict_skips=0
jobs="${PLUGIN_TEST_JOBS:-1}"
root=""
shard_spec="0/1"
suites_from=""
budget=""
budget_given=0
timings_file=""
named_suites=()
list=0
while (($# > 0)); do
  case "$1" in
  --strict-skips) strict_skips=1 ;;
  --timings)
    [[ $# -ge 2 && -n "$2" ]] || usage
    timings_file="$2"
    shift
    ;;
  --timings=*)
    timings_file="${1#--timings=}"
    [[ -n "$timings_file" ]] || usage
    ;;
  --budget)
    [[ $# -ge 2 ]] || usage
    budget="$2"
    budget_given=1
    shift
    ;;
  --budget=*) budget="${1#--budget=}" budget_given=1 ;;
  --list) list=1 ;;
  --suites-from)
    [[ $# -ge 2 ]] || usage
    suites_from="$2"
    shift
    ;;
  --suites-from=*) suites_from="${1#--suites-from=}" ;;
  --jobs)
    [[ $# -ge 2 ]] || usage
    jobs="$2"
    shift
    ;;
  --jobs=*) jobs="${1#--jobs=}" ;;
  --root)
    [[ $# -ge 2 ]] || usage
    root="$2"
    shift
    ;;
  --shard)
    [[ $# -ge 2 ]] || usage
    shard_spec="$2"
    shift
    ;;
  --shard=*) shard_spec="${1#--shard=}" ;;
  -*) usage ;;
  *) named_suites+=("$1") ;;
  esac
  shift
done
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --jobs must be a positive integer (got '$jobs')" >&2
  exit 2
fi
share_margin="${PLUGIN_TEST_SHARE_MARGIN:-3}"
share_default="${PLUGIN_TEST_SHARE_DEFAULT:-30}"
share_warn_only="${PLUGIN_TEST_SHARE_WARN_ONLY:-0}"
if ((budget_given)); then
  if [[ "$share_warn_only" != [01] ]]; then
    echo "error: PLUGIN_TEST_SHARE_WARN_ONLY must be 0 or 1 (got '$share_warn_only')" >&2
    exit 2
  fi
  for v in "--budget:$budget" "PLUGIN_TEST_SHARE_MARGIN:$share_margin" "PLUGIN_TEST_SHARE_DEFAULT:$share_default"; do
    if [[ ! "${v#*:}" =~ ^[1-9][0-9]*$ ]]; then
      echo "error: ${v%%:*} must be a positive integer (got '${v#*:}')" >&2
      exit 2
    fi
  done
fi
suite_budget="${PLUGIN_TEST_SUITE_BUDGET:-}"
if [[ -z "$suite_budget" ]]; then
  suite_budget=0
  [[ "${GITHUB_ACTIONS:-}" != true ]] || suite_budget=1
elif [[ "$suite_budget" != [01] ]]; then
  echo "error: PLUGIN_TEST_SUITE_BUDGET must be 0 or 1 (got '$suite_budget')" >&2
  exit 2
fi
suite_warn="${PLUGIN_TEST_SUITE_WARN:-120}"
suite_ceiling="${PLUGIN_TEST_SUITE_CEILING:-300}"
if ((suite_budget)); then
  for v in "PLUGIN_TEST_SUITE_WARN:$suite_warn" "PLUGIN_TEST_SUITE_CEILING:$suite_ceiling"; do
    if [[ ! "${v#*:}" =~ ^[1-9][0-9]*$ ]]; then
      echo "error: ${v%%:*} must be a positive integer (got '${v#*:}')" >&2
      exit 2
    fi
  done
fi
if ! parse_shard "$shard_spec"; then
  echo "error: --shard wants <index>/<total> with total >= 1 and 0 <= index < total (got '$shard_spec')" >&2
  exit 2
fi
# Resolved BEFORE the cd below, so a relative path means what the caller meant.
if [[ -n "$suites_from" ]]; then
  if [[ ! -f "$suites_from" ]]; then
    echo "error: --suites-from file not found: $suites_from" >&2
    exit 2
  fi
  suites_from="$(cd "$(dirname "$suites_from")" && pwd)/$(basename "$suites_from")" || exit 2
fi
if [[ -n "$timings_file" ]]; then
  if [[ ! -d "$(dirname "$timings_file")" ]]; then
    echo "error: --timings directory not found: $(dirname "$timings_file")" >&2
    exit 2
  fi
  timings_file="$(cd "$(dirname "$timings_file")" && pwd)/$(basename "$timings_file")" || exit 2
  : >"$timings_file" || exit 2
fi

if [[ -n "$root" ]]; then
  cd "$root" || exit 2
else
  cd "$script_dir/.." || exit 1
fi

mapfile -t tests < <(find plugins .claude/hooks scripts lib -type f -name '*.test.sh' 2>/dev/null | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "error: no test suites found under plugins/, .claude/hooks/, scripts/ or lib/ (*.test.sh)" >&2
  exit 2
fi
if ((list)); then
  printf '%s\n' "${tests[@]}"
  exit 0
fi

declare -A discovered=()
for t in "${tests[@]}"; do
  discovered["$t"]=1
done
# read_suite_list <file> <assoc-name>: the serial and advisory lists, one
# repo-relative suite path per line, `#` comments and blank lines ignored. Read
# before anything runs so a stale entry fails the run up front rather than
# after minutes of suites.
read_suite_list() {
  local file="$1" line
  local -n into="$2"
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    if [[ -z "${discovered[$line]+x}" ]]; then
      echo "error: $file names '$line', which matches no discovered suite; remove the stale entry" >&2
      exit 2
    fi
    # shellcheck disable=SC2034 # a nameref; the caller's array is what it writes.
    into["$line"]=1
  done <"$file"
}
declare -A is_serial=() is_advisory=()
read_suite_list "$SERIAL_LIST" is_serial
read_suite_list "$ADVISORY_LIST" is_advisory
[[ "${PLUGIN_TEST_ADVISORY:-}" == 1 ]] || is_advisory=()
# The exceptions list: one `<suite> <ceiling-seconds>` row per suite, with the
# same stale guard.
declare -A exception_ceiling=()
if [[ -f "$EXCEPTIONS_LIST" ]]; then
  while read -r path secs extra || [[ -n "$path" ]]; do
    [[ -n "$path" && "$path" != \#* ]] || continue
    if [[ ! "$secs" =~ ^[1-9][0-9]*$ || -n "$extra" && "$extra" != \#* ]]; then
      echo "error: $EXCEPTIONS_LIST row for '$path' wants '<suite> <ceiling-seconds>'" >&2
      exit 2
    fi
    if [[ -z "${discovered[$path]+x}" ]]; then
      echo "error: $EXCEPTIONS_LIST names '$path', which matches no discovered suite; remove the stale entry" >&2
      exit 2
    fi
    exception_ceiling["$path"]="$secs"
  done <"$EXCEPTIONS_LIST"
fi
# The supplied selection replaces the discovered corpus HERE: after the stale
# guard, so the allowlist is still matched against the full discovery, and
# before the shard, so --suites-from and --shard compose the way --shard alone
# always did.
if [[ -n "$suites_from" ]] || ((${#named_suites[@]} > 0)); then
  supplied=()
  if [[ -n "$suites_from" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      if [[ ! -f "$line" ]]; then
        echo "error: --suites-from names '$line', which is not a file" >&2
        exit 2
      fi
      supplied+=("$line")
    done <"$suites_from"
  fi
  for line in ${named_suites[@]+"${named_suites[@]}"}; do
    if [[ ! -f "$line" ]]; then
      echo "error: suite argument '$line' is not a file (suite arguments are repo-relative)" >&2
      exit 2
    fi
    supplied+=("$line")
  done
  if ((${#supplied[@]} == 0)); then
    echo "The supplied selection is empty; nothing to run."
    exit 0
  fi
  tests=("${supplied[@]}")
fi
# The partition, AFTER the stale guard so an allowlist entry that lands on
# another leg is still matched against the full discovery.
if ((shard_total > 1)); then
  leg=()
  for ((si = shard_index; si < ${#tests[@]}; si += shard_total)); do
    leg+=("${tests[$si]}")
  done
  echo "shard: leg $shard_index of $shard_total keeps ${#leg[@]} of ${#tests[@]} suite(s)."
  if ((${#leg[@]} == 0)); then
    echo "This leg has no suites to run; the other legs carry the corpus."
    exit 0
  fi
  tests=("${leg[@]}")
fi
serial_suites=()
parallel_suites=()
suite_keys=()
for i in "${!tests[@]}"; do
  t="${tests[$i]}"
  # One key per suite, reused by the dispatch below and by the summary loop so
  # both address the same capture. Assigned BY INDEX rather than appended: the
  # key has to follow the position in `tests`, and an append would only agree
  # with that while the array stays dense.
  suite_keys[i]="$(printf '%06d' "$i")"
  if [[ -n "${is_serial[$t]+x}" ]]; then
    serial_suites+=("${suite_keys[$i]}:$t")
  else
    parallel_suites+=("${suite_keys[$i]}:$t")
  fi
done

# Longest first, as scripts/selection-audit.sh orders its traces. The sort is
# stable, so unlisted suites (0 s) keep their order. Each entry keeps its key,
# so the summary still reads in corpus order.
if ((${#parallel_suites[@]} > 1)) && [[ -s "$SECONDS_LIST" ]]; then
  mapfile -t parallel_suites < <(printf '%s\n' "${parallel_suites[@]}" |
    awk 'NR == FNR { if (!/^#/) s[$1] = $2; next } { p = $0; sub(/^[0-9]+:/, "", p); print (p in s ? s[p] : 0) "\t" $0 }' "$SECONDS_LIST" - |
    sort -s -t $'\t' -k1,1nr | cut -f2-)
fi

# suite_share <suite>: its median times the margin, floored at the default.
declare -A median=()
if [[ -n "$budget" && -s "$SECONDS_LIST" ]]; then
  while read -r path secs _; do
    [[ "$path" == \#* || ! "$secs" =~ ^[0-9]+$ ]] || median["$path"]="$secs"
  done <"$SECONDS_LIST"
fi
suite_share() {
  local share=$((${median[$1]:-0} * share_margin))
  ((share > share_default)) || share="$share_default"
  printf '%s' "$share"
}
if [[ -n "$budget" ]]; then
  for t in "${tests[@]}"; do
    [[ -n "${median[$t]+x}" ]] ||
      echo "note: $t has no median in $SECONDS_LIST, so it gets the default ${share_default}s share" >&2
  done
fi

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT
export PLUGIN_TEST_LOG_DIR="$log_dir"

if command -v git >/dev/null 2>&1; then
  echo "Runner git: $(git --version)"
else
  echo "Runner git: unavailable"
fi
echo "Suites: ${#tests[@]} (${#serial_suites[@]} serial, ${#parallel_suites[@]} across up to $jobs job(s))"
# A fresh nonce, printed before any suite runs and repeated in each advisory
# warning, so babysit_postmerge.py credits only the runner's own warnings. It
# is never exported: no suite can print it.
advisory_nonce=''
if ((${#is_advisory[@]} > 0)); then
  advisory_nonce="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  echo "Advisory nonce: $advisory_nonce"
fi

run_start=$SECONDS
for t in ${serial_suites[@]+"${serial_suites[@]}"}; do
  bash "$runner" --worker "$t"
done
if [[ ${#parallel_suites[@]} -gt 0 ]]; then
  # xargs appends one indexed suite path after `--worker` per invocation.
  printf '%s\0' "${parallel_suites[@]}" | xargs -0 -n 1 -P "$jobs" bash "$runner" --worker
fi
run_seconds=$((SECONDS - run_start))

# suite_annotate <error|warning> <suite> <message>: one annotation titled by the
# suite, so a log reader can group results by suite. Escapes follow actions/toolkit
# packages/core/src/command.ts (escapeProperty, escapeData): % \r \n in both,
# and : , in the title property, since a suite path may contain either.
suite_annotate() {
  local level="$1" title="$2" msg="$3"
  title="${title//%/%25}"
  title="${title//$'\r'/%0D}"
  title="${title//$'\n'/%0A}"
  title="${title//:/%3A}"
  title="${title//,/%2C}"
  msg="${msg//%/%25}"
  msg="${msg//$'\r'/%0D}"
  msg="${msg//$'\n'/%0A}"
  echo "::$level title=$title::$msg"
}

failed=0
advisory_failed=0
total_optional_skips=0
total_discriminating_skips=0
skipped_suites=()
timings=()

for i in "${!tests[@]}"; do
  t="${tests[$i]}"
  log="$log_dir/${suite_keys[$i]}"
  if [[ ! -f "$log.rc" ]]; then
    echo "FAIL: $t (no result recorded; the worker never reported)" >&2
    suite_annotate error "$t" "$t failed (no result recorded; the worker never reported)"
    failed=1
    continue
  fi
  rc="$(<"$log.rc")"
  [[ -z "$timings_file" ]] || printf '%s\t%s\t%s\n' "$t" "$(<"$log.secs")" "$rc" >>"$timings_file"
  if ((rc != 0)) && [[ -n "${is_advisory[$t]+x}" ]]; then
    suite_annotate warning "$t" "$t failed (exit $rc) but is advisory on this run (nonce $advisory_nonce; PLUGIN_TEST_ADVISORY=1, scripts/run-plugin-tests-advisory.txt)"
    advisory_failed=$((advisory_failed + 1))
  elif ((rc != 0)); then
    suite_annotate error "$t" "$t failed (exit $rc)"
    failed=1
  fi
  if [[ -n "$budget" ]]; then
    secs="$(<"$log.secs")"
    timings+=("$secs"$'\t'"$t")
    share="$(suite_share "$t")"
    if ((secs > share && share_warn_only)); then
      echo "OVER SHARE: $t took ${secs}s, over its ${share}s share of the budget (a warning: PLUGIN_TEST_SHARE_WARN_ONLY=1)" >&2
      suite_annotate warning "$t" "$t took ${secs}s, over its ${share}s share of the budget"
    elif ((secs > share)); then
      echo "FAIL: $t took ${secs}s, over its ${share}s share of the budget" >&2
      suite_annotate error "$t" "$t took ${secs}s, over its ${share}s share of the budget"
      failed=1
    fi
  fi
  if ((suite_budget)); then
    secs="$(<"$log.secs")"
    ceiling="${exception_ceiling[$t]:-$suite_ceiling}"
    if ((secs > ceiling)); then
      # `FAIL: <suite>` alone on its line, the shape log readers attribute.
      printf 'FAIL: %s\n  took %ss, over its %ss per-suite ceiling\n' "$t" "$secs" "$ceiling" >&2
      suite_annotate error "$t" "$t took ${secs}s, over its ${ceiling}s per-suite ceiling (README.md, Per-suite time budget in CI)"
      failed=1
    elif ((secs > suite_warn)); then
      echo "SLOW: $t took ${secs}s, over the ${suite_warn}s per-suite threshold"
      suite_annotate warning "$t" "$t took ${secs}s, over the ${suite_warn}s per-suite threshold (README.md, Per-suite time budget in CI)"
    fi
  fi
  opt_skips="$(grep -c '^SKIP:' "$log.out" 2>/dev/null || true)"
  disc_skips="$(grep -c '^DISCRIMINATING SKIP:' "$log.out" 2>/dev/null || true)"
  total_optional_skips=$((total_optional_skips + opt_skips))
  total_discriminating_skips=$((total_discriminating_skips + disc_skips))
  if ((opt_skips > 0)); then
    first_reason="$(grep -m1 '^SKIP:' "$log.out")"
    skipped_suites+=("$t — ${opt_skips} SKIP(s), first: ${first_reason#SKIP: }")
  fi
  if ((disc_skips > 0)); then
    echo "DISCRIMINATING SKIP: $t vacated $disc_skips discriminating case(s)" >&2
  fi
done

echo ""
echo "Plugin test aggregate: ${total_optional_skips} optional SKIP(s), ${total_discriminating_skips} DISCRIMINATING SKIP(s)."
if ((${#skipped_suites[@]} > 0)); then
  echo "Suites with skipped coverage (exit 0 here is NOT evidence those cases ran):"
  for s in "${skipped_suites[@]}"; do
    echo "  SKIPPED: $s"
  done
fi

if [[ -n "$budget" ]] && ((run_seconds > budget)); then
  {
    echo "OVER BUDGET: the suites took ${run_seconds}s, over the ${budget}s budget. Slowest:"
    printf '%s\n' ${timings[@]+"${timings[@]}"} | sort -t $'\t' -k1,1nr | head -n 3 |
      while IFS=$'\t' read -r secs t; do echo "  ${secs}s $t"; done
  } >&2
elif [[ -n "$budget" ]]; then
  echo "The suites took ${run_seconds}s of the ${budget}s budget."
fi

if ((total_discriminating_skips > 0)); then
  {
    echo "DISCRIMINATING SKIP(s) mean discriminating coverage did not run —"
    echo "this run is not equivalent to a full pass."
  } >&2
  failed=1
fi

if ((strict_skips)) && ((total_optional_skips > 0)); then
  {
    echo "--strict-skips: ${total_optional_skips} optional SKIP(s) occurred in an"
    echo "environment declared to have the full toolchain — treating as failure."
  } >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  echo "One or more plugin tests failed." >&2
  exit 1
fi
if ((advisory_failed > 0)); then
  echo "All required plugin tests passed; ${advisory_failed} advisory suite(s) FAILED (named above)."
elif ((total_optional_skips > 0)); then
  echo "All executed plugin tests passed; ${total_optional_skips} case(s) skipped (named above)."
else
  echo "All plugin tests passed."
fi
