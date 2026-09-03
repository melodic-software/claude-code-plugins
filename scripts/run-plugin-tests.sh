#!/usr/bin/env bash
# Run every plugin contract test (plugins/**/*.test.sh) plus the repo-local
# hook tests (.claude/hooks/*.test.sh) and fail if any fails. The repo-local
# hooks are tracked policy with the same test conventions as plugin hooks.
#
#   scripts/run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR]
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
# it excuses.
#
# Output stays readable under parallelism. Every suite's output is captured to
# a file and replayed as one block under a lock (`=== path ===`, the suite's own
# lines, then `PASS:` or `FAIL:`), so blocks from concurrent suites never
# interleave and the per-suite markers that CI log tooling reads survive. The
# block is printed the moment its suite finishes, so progress stays visible.
#
# --root DIR discovers suites under DIR instead of the repository (test
# injection for this runner's own suite, scripts/run-plugin-tests.test.sh).
set -uo pipefail

# Fixture isolation (#2840). `-C` only changes directory, while an exported
# ABSOLUTE GIT_DIR overrides repository DISCOVERY, and `git config`'s default
# --local scope follows whatever gitdir that resolves to. A suite spawned with
# those inherited writes its throwaway fixture identity into the CALLER's
# .git/config — shared by every worktree of the clone — instead of into its
# fixture. What exported them does not matter: the real incident came from an
# ad-hoc tool invocation rather than from a git hook, so this runner clears them
# unconditionally and isolates every suite it spawns, whatever idiom that suite
# uses internally.
#
# GIT_CONFIG is cleared here too and is a DISTINCT path rather than another
# spelling of the same one: it replaces the file the `git config` subcommand
# reads and writes, so a fixture identity write follows it regardless of -C, of
# GIT_DIR, and of the working directory.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$script_dir/${BASH_SOURCE[0]##*/}"
SERIAL_LIST="${PLUGIN_TEST_SERIAL_LIST:-$script_dir/run-plugin-tests-serial.txt}"

usage() {
  echo "usage: run-plugin-tests.sh [--strict-skips] [--jobs N] [--root DIR]" >&2
  exit 2
}

# --worker <NNNNNN:suite>: internal. Runs ONE suite with its output captured
# under $PLUGIN_TEST_LOG_DIR, records its exit status beside the capture, then
# prints the whole block under the print lock. Reached only from the dispatch
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
  bash "$suite" >"$log.out" 2>&1 || rc=$?
  printf '%s\n' "$rc" >"$log.rc"
  until mkdir "$log_dir/.print-lock" 2>/dev/null; do sleep 0.02; done
  echo "=== $suite ==="
  cat "$log.out"
  if ((rc == 0)); then
    echo "PASS: $suite"
  else
    echo "FAIL: $suite" >&2
  fi
  rmdir "$log_dir/.print-lock"
  exit 0
fi

strict_skips=0
jobs="${PLUGIN_TEST_JOBS:-1}"
root=""
while (($# > 0)); do
  case "$1" in
  --strict-skips) strict_skips=1 ;;
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
  *) usage ;;
  esac
  shift
done
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --jobs must be a positive integer (got '$jobs')" >&2
  exit 2
fi

if [[ -n "$root" ]]; then
  cd "$root" || exit 2
else
  cd "$script_dir/.." || exit 1
fi

mapfile -t tests < <(find plugins .claude/hooks -type f -name '*.test.sh' 2>/dev/null | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "error: no plugin tests found under plugins/**/*.test.sh" >&2
  exit 2
fi

# The serial allowlist: one repo-relative suite path per line, `#` comments and
# blank lines ignored. Read before anything runs so a stale entry fails the run
# up front rather than after minutes of suites.
serial_entries=()
if [[ -f "$SERIAL_LIST" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    serial_entries+=("$line")
  done <"$SERIAL_LIST"
fi
declare -A is_serial=()
for s in ${serial_entries[@]+"${serial_entries[@]}"}; do
  found=0
  for t in "${tests[@]}"; do
    if [[ "$t" == "$s" ]]; then
      found=1
      break
    fi
  done
  if ((found == 0)); then
    echo "error: $SERIAL_LIST names '$s', which matches no discovered suite; remove the stale entry" >&2
    exit 2
  fi
  is_serial["$s"]=1
done
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

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT
export PLUGIN_TEST_LOG_DIR="$log_dir"

if command -v git >/dev/null 2>&1; then
  echo "Runner git: $(git --version)"
else
  echo "Runner git: unavailable"
fi
echo "Suites: ${#tests[@]} (${#serial_suites[@]} serial, ${#parallel_suites[@]} across up to $jobs job(s))"

for t in ${serial_suites[@]+"${serial_suites[@]}"}; do
  bash "$runner" --worker "$t"
done
if [[ ${#parallel_suites[@]} -gt 0 ]]; then
  # xargs appends one indexed suite path after `--worker` per invocation.
  printf '%s\0' "${parallel_suites[@]}" | xargs -0 -n 1 -P "$jobs" bash "$runner" --worker
fi

failed=0
total_optional_skips=0
total_discriminating_skips=0
skipped_suites=()

for i in "${!tests[@]}"; do
  t="${tests[$i]}"
  log="$log_dir/${suite_keys[$i]}"
  if [[ ! -f "$log.rc" ]]; then
    echo "FAIL: $t (no result recorded; the worker never reported)" >&2
    failed=1
    continue
  fi
  rc="$(<"$log.rc")"
  ((rc == 0)) || failed=1
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
if ((total_optional_skips > 0)); then
  echo "All executed plugin tests passed; ${total_optional_skips} case(s) skipped (named above)."
else
  echo "All plugin tests passed."
fi
