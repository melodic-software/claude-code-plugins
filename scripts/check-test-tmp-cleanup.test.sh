#!/usr/bin/env bash
# Black-box contract test for check-test-tmp-cleanup.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repository with
# fixture *.test.sh files and a baseline, runs the checker against it, and
# asserts on exit code and output. The SUT resolves the repository root
# relative to its own location, so the fixture carries a copy of it under
# scripts/ and every case commits its files so `git ls-files` sees them.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-test-tmp-cleanup.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# The fixture bodies name the command without spelling it in one piece, so this
# suite is not itself a temp-creating suite the checker would flag.
MK="mk"'temp'

# shellcheck disable=SC2016  # the fixture body must reach the file unexpanded
write_clean() { printf 'd=$(%s -d)\ntrap '"'"'rm -rf "$d"'"'"' EXIT\n' "$MK" >"$1"; }
# shellcheck disable=SC2016  # the fixture body must reach the file unexpanded
write_offender() { printf 'd=$(%s -d)\nrm -rf "$d"\n' "$MK" >"$1"; }
write_comment_only() { printf '# uses %s somewhere else\necho hi\n' "$MK" >"$1"; }

# mk_repo <out-var>: a repo with one clean suite, one comment-only suite, and an
# empty baseline. The builder assigns through a nameref, which shellcheck
# cannot follow.
mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --git || return 1
  dir="${!1}"
  mkdir -p "$dir/plugins/p"
  write_clean "$dir/plugins/p/clean.test.sh"
  write_comment_only "$dir/plugins/p/comment.test.sh"
  : >"$dir/scripts/test-tmp-cleanup-baseline.txt"
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
# <setup> runs inside the fixture root before everything is committed; each
# <must-name> must appear in the output of a failing run.
run_case() {
  local label="$1" expected="$2" setup="$3"
  shift 3
  local repo out rc s
  mk_repo repo || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$repo" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  out="$(bash "$repo/scripts/check-test-tmp-cleanup.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$out"; then
      fail "$label: '$s' not named in output: $out"
      return
    fi
  done
  ok "$label"
}

run_case "clean suites pass" 0 ":"

run_case "an offender not in the baseline fails and is named" 1 \
  "$(declare -f write_offender); MK=$MK; write_offender plugins/p/bad.test.sh" \
  "plugins/p/bad.test.sh"

run_case "a baselined offender passes" 0 \
  "$(declare -f write_offender); MK=$MK; write_offender plugins/p/bad.test.sh; printf 'plugins/p/bad.test.sh  # known\n' >scripts/test-tmp-cleanup-baseline.txt"

run_case "a baselined file that now traps fails as stale" 1 \
  "printf 'plugins/p/clean.test.sh\n' >scripts/test-tmp-cleanup-baseline.txt" \
  "plugins/p/clean.test.sh: scripts/test-tmp-cleanup-baseline.txt lists it, but it no longer offends"

run_case "a baselined file that is gone fails as stale" 1 \
  "printf 'plugins/p/gone.test.sh\n' >scripts/test-tmp-cleanup-baseline.txt" \
  "plugins/p/gone.test.sh: scripts/test-tmp-cleanup-baseline.txt lists it, but the file does not exist"

run_case "a missing baseline is an environment error" 2 \
  "rm scripts/test-tmp-cleanup-baseline.txt"

# Findings on stderr only.
repo=""
if mk_repo repo; then
  write_offender "$repo/plugins/p/bad.test.sh"
  git_test_config "$repo" add -A >/dev/null
  git_test_config "$repo" commit -qm case >/dev/null
  stdout="$(bash "$repo/scripts/check-test-tmp-cleanup.sh" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 1 && -z "$stdout" ]]; then
    ok "discover mode exits 1 with nothing on stdout"
  else
    fail "discover mode should exit 1 with an empty stdout (rc=$rc): $stdout"
  fi
else
  fail "discover mode: fixture build failed"
fi

bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
