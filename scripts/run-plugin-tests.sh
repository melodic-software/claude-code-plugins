#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG CLAUDE_PLUGIN_DATA

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$script_dir/${BASH_SOURCE[0]##*/}"
# shellcheck source=lib/test-git-env.sh
. "$script_dir/lib/test-git-env.sh"
# shellcheck source=lib/read-list.sh
. "$script_dir/lib/read-list.sh"
# shellcheck source=lib/shard-spec.sh
. "$script_dir/lib/shard-spec.sh"
SERIAL_LIST="${PLUGIN_TEST_SERIAL_LIST:-$script_dir/run-plugin-tests-serial.txt}"
SECONDS_LIST="${PLUGIN_TEST_SECONDS_LIST:-$script_dir/suite-seconds.txt}"
ADVISORY_LIST="${PLUGIN_TEST_ADVISORY_LIST:-$script_dir/run-plugin-tests-advisory.txt}"
EXCEPTIONS_LIST="${PLUGIN_TEST_SUITE_EXCEPTIONS:-$script_dir/suite-budget-exceptions.txt}"

usage() {
  echo "usage: run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR] [--shard I/N] [--suites-from FILE] [--budget SECONDS] [--timings FILE] [SUITE ...] | --list [--root DIR]" >&2
  exit 2
}

if [[ "${1:-}" == "--worker" ]]; then
  keyed="${2:?--worker needs an indexed suite path}"
  key="${keyed%%:*}"
  suite="${keyed#*:}"
  log_dir="${PLUGIN_TEST_LOG_DIR:?--worker needs PLUGIN_TEST_LOG_DIR}"
  log="$log_dir/$key"
  deadline="${PLUGIN_TEST_DEADLINE:-}"
  unset PLUGIN_TEST_DEADLINE PLUGIN_TEST_LEFT_FILE
  if [[ -n "$deadline" ]]; then
    printf -v now '%(%s)T' -1
    if ((now >= deadline)); then
      : >"$log.left"
      exit 0
    fi
  fi
  rc=0
  test_git_env::isolate "$log.gitconfig" || exit 2
  # Concurrent pwsh starts sharing one MultiCoreJit profile can crash: https://github.com/dotnet/runtime/issues/121977
  export DOTNET_MultiCoreJitMinNumCpus=65535
  start=$SECONDS
  bash "$suite" >"$log.out" 2>&1 || rc=$?
  secs=$((SECONDS - start))
  printf '%s\n' "$secs" >"$log.secs"
  printf '%s\n' "$rc" >"$log.rc"
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
require_positive_ints() {
  local v
  for v in "$@"; do
    if [[ ! "${v#*:}" =~ ^[1-9][0-9]*$ ]]; then
      echo "error: ${v%%:*} must be a positive integer (got '${v#*:}')" >&2
      exit 2
    fi
  done
}
if [[ -v PLUGIN_TEST_DEADLINE && ! "$PLUGIN_TEST_DEADLINE" =~ ^[0-9]+$ ]]; then
  echo "error: PLUGIN_TEST_DEADLINE must be epoch seconds (got '$PLUGIN_TEST_DEADLINE')" >&2
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
  require_positive_ints "--budget:$budget" "PLUGIN_TEST_SHARE_MARGIN:$share_margin" "PLUGIN_TEST_SHARE_DEFAULT:$share_default"
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
  require_positive_ints "PLUGIN_TEST_SUITE_WARN:$suite_warn" "PLUGIN_TEST_SUITE_CEILING:$suite_ceiling"
fi
if ! parse_shard "$shard_spec"; then
  echo "error: --shard wants <index>/<total> with total >= 1 and 0 <= index < total (got '$shard_spec')" >&2
  exit 2
fi
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

mapfile -t tests < <(find plugins .claude/hooks .github scripts lib -type f -name '*.test.sh' 2>/dev/null | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "error: no test suites found under plugins/, .claude/hooks/, .github/, scripts/ or lib/ (*.test.sh)" >&2
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
read_suite_list() {
  local file="$1" line entries=()
  local -n into="$2"
  [[ -f "$file" ]] || return 0
  read_list::into entries "$file" --comments inline || exit 2
  for line in ${entries[@]+"${entries[@]}"}; do
    if [[ -z "${discovered[$line]+x}" ]]; then
      echo "error: $file names '$line', which matches no discovered suite; remove the stale entry" >&2
      exit 2
    fi
    # shellcheck disable=SC2034 # a nameref; the caller's array is what it writes.
    into["$line"]=1
  done
}
declare -A is_serial=() is_advisory=()
read_suite_list "$SERIAL_LIST" is_serial
read_suite_list "$ADVISORY_LIST" is_advisory
[[ "${PLUGIN_TEST_ADVISORY:-}" == 1 ]] || is_advisory=()
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
  suite_keys[i]="$(printf '%06d' "$i")"
  if [[ -n "${is_serial[$t]+x}" ]]; then
    serial_suites+=("${suite_keys[$i]}:$t")
  else
    parallel_suites+=("${suite_keys[$i]}:$t")
  fi
done

if ((${#parallel_suites[@]} > 1)) && [[ -s "$SECONDS_LIST" ]]; then
  mapfile -t parallel_suites < <(printf '%s\n' "${parallel_suites[@]}" |
    awk 'NR == FNR { if (!/^#/) s[$1] = $2; next } { p = $0; sub(/^[0-9]+:/, "", p); print (p in s ? s[p] : 0) "\t" $0 }' "$SECONDS_LIST" - |
    sort -s -t $'\t' -k1,1nr | cut -f2-)
fi

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
  printf '%s\0' "${parallel_suites[@]}" | xargs -0 -n 1 -P "$jobs" bash "$runner" --worker
fi
run_seconds=$((SECONDS - run_start))

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

fail_excerpt() {
  if grep -q -E '^(FAIL|not ok)' "$2"; then
    printf '  Failing lines of %s:\n' "$1"
    grep -m 20 -E '^(FAIL|not ok)' "$2" | sed 's/^/    | /'
  fi
  printf '  Last 80 lines of %s:\n' "$1"
  tail -n 80 "$2" | sed 's/^/    | /'
}

failed=0
advisory_failed=0
total_optional_skips=0
total_discriminating_skips=0
skipped_suites=()
timings=()
left=()

for i in "${!tests[@]}"; do
  t="${tests[$i]}"
  log="$log_dir/${suite_keys[$i]}"
  if [[ ! -f "$log.rc" && -n "${PLUGIN_TEST_DEADLINE:-}" && -f "$log.left" ]]; then
    left+=("$t")
    continue
  fi
  if [[ ! -f "$log.rc" ]]; then
    echo "FAIL: $t (no result recorded; the worker never reported)" >&2
    suite_annotate error "$t" "$t failed (no result recorded; the worker never reported)"
    failed=1
    continue
  fi
  rc="$(<"$log.rc")"
  secs="$(<"$log.secs")"
  [[ -z "$timings_file" ]] || printf '%s\t%s\t%s\n' "$t" "$secs" "$rc" >>"$timings_file"
  if ((rc != 0)) && [[ -n "${is_advisory[$t]+x}" ]]; then
    suite_annotate warning "$t" "$t failed (exit $rc) but is advisory on this run (nonce $advisory_nonce; PLUGIN_TEST_ADVISORY=1, scripts/run-plugin-tests-advisory.txt)"
    fail_excerpt "$t" "$log.out"
    advisory_failed=$((advisory_failed + 1))
  elif ((rc != 0)); then
    suite_annotate error "$t" "$t failed (exit $rc)"
    fail_excerpt "$t" "$log.out"
    failed=1
  fi
  if [[ -n "$budget" ]]; then
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
    ceiling="${exception_ceiling[$t]:-$suite_ceiling}"
    if ((secs > ceiling)); then
      printf 'FAIL: %s\n  took %ss, over its %ss per-suite ceiling\n' "$t" "$secs" "$ceiling" >&2
      suite_annotate error "$t" "$t took ${secs}s, over its ${ceiling}s per-suite ceiling (scripts/README.md, Per-suite time budget in CI)"
      failed=1
    elif ((secs > suite_warn)); then
      echo "SLOW: $t took ${secs}s, over the ${suite_warn}s per-suite threshold"
      suite_annotate warning "$t" "$t took ${secs}s, over the ${suite_warn}s per-suite threshold (scripts/README.md, Per-suite time budget in CI)"
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

if ((${#left[@]} > 0)); then
  printf 'LEFT TO CI: %s\n' "${left[@]}"
  if [[ -n "${PLUGIN_TEST_LEFT_FILE:-}" ]] && ! printf '%s\n' "${left[@]}" >"$PLUGIN_TEST_LEFT_FILE"; then
    echo "error: cannot write PLUGIN_TEST_LEFT_FILE: $PLUGIN_TEST_LEFT_FILE" >&2
    exit 2
  fi
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
if ((${#left[@]} > 0)); then
  echo "The plugin tests that ran passed; ${#left[@]} suite(s) left to CI (named above)."
elif ((advisory_failed > 0)); then
  echo "All required plugin tests passed; ${advisory_failed} advisory suite(s) FAILED (named above)."
elif ((total_optional_skips > 0)); then
  echo "All executed plugin tests passed; ${total_optional_skips} case(s) skipped (named above)."
else
  echo "All plugin tests passed."
fi
