#!/usr/bin/env bash
# Black-box contract test for check-spoke-plugin-root.sh.
#
# Self-contained and cwd-independent: builds a throwaway tree with fixture
# spokes and a baseline, runs the checker against it, and asserts on exit code
# and output. Mutates only its own mktemp dir. The SUT resolves the repository
# root relative to its own location, so the fixture tree carries a copy of it
# under scripts/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-spoke-plugin-root.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

SKILL=plugins/alpha/skills/audit

# mk_tree <out-var>: a tree with one baselined offender, one clean spoke that
# cites <skill-dir>, and a SKILL.md that legitimately holds the token.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label spoke-plugin-root || return 1
  dir="${!1}"
  mkdir -p "$dir/$SKILL/context" "$dir/$SKILL/reference/sub" "$dir/$SKILL/references"
  # shellcheck disable=SC2016  # the token is literal fixture text
  {
    printf 'run ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/a.sh\n' >"$dir/$SKILL/context/old.md"
    printf 'run ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/a.sh\n' >"$dir/$SKILL/SKILL.md"
  }
  printf 'run <skill-dir>/scripts/a.sh\n' >"$dir/$SKILL/context/new.md"
  printf '# spokes that predate the gate\n%s/context/old.md 1  # justified: prose\n' "$SKILL" \
    >"$dir/scripts/spoke-plugin-root-baseline.txt"
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
# <setup> runs inside the fixture root; each <must-name> must appear in the
# output of a failing run.
run_case() {
  local label="$1" expected="$2" setup="$3"
  shift 3
  local tree out rc s
  mk_tree tree || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$tree" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  out="$(bash "$tree/scripts/check-spoke-plugin-root.sh" --check 2>&1)"
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

run_case "clean tree with a baselined spoke passes" 0 ":"

# shellcheck disable=SC2016  # the token is literal fixture text in every setup below
run_case "a new unlisted spoke fails and names it" 1 \
  "printf 'x \${CLAUDE_PLUGIN_ROOT}/y\n' >$SKILL/context/fresh.md" \
  "$SKILL/context/fresh.md: contains"

# shellcheck disable=SC2016
run_case "a spoke under reference/ nested deeper fails" 1 \
  "printf 'x \${CLAUDE_PLUGIN_ROOT}/y\n' >$SKILL/reference/sub/deep.md" \
  "$SKILL/reference/sub/deep.md: contains"

# shellcheck disable=SC2016
run_case "a spoke under references/ fails" 1 \
  "printf 'x \${CLAUDE_PLUGIN_ROOT}/y\n' >$SKILL/references/r.md" \
  "$SKILL/references/r.md: contains"

# shellcheck disable=SC2016
run_case "a token outside the spoke directories is not an offender" 0 \
  "mkdir -p $SKILL/scripts && printf 'x \${CLAUDE_PLUGIN_ROOT}/y\n' >$SKILL/scripts/a.sh"

run_case "a baselined spoke that lost its token fails as stale" 1 \
  "printf 'run <skill-dir>/scripts/a.sh\n' >$SKILL/context/old.md" \
  "$SKILL/context/old.md: scripts/spoke-plugin-root-baseline.txt lists it, but it no longer contains the token"

run_case "a baseline entry naming a missing file fails as stale" 1 \
  "rm $SKILL/context/old.md" \
  "$SKILL/context/old.md: scripts/spoke-plugin-root-baseline.txt lists it, but the file does not exist"

run_case "an empty baseline passes on a tree with no offender" 0 \
  "rm $SKILL/context/old.md && : >scripts/spoke-plugin-root-baseline.txt"

run_case "a tree with no skills passes" 0 \
  "rm -r plugins && : >scripts/spoke-plugin-root-baseline.txt"

# shellcheck disable=SC2016
run_case "an added hit in a baselined spoke fails and names the counts" 1 \
  "printf 'run \${CLAUDE_PLUGIN_ROOT}/b.sh and \${CLAUDE_PLUGIN_ROOT}/c.sh\n' >>$SKILL/context/old.md" \
  "$SKILL/context/old.md: has 3 occurrence(s)" "allows 1"

# shellcheck disable=SC2016
run_case "two hits on one line count as two" 1 \
  "printf 'run \${CLAUDE_PLUGIN_ROOT}/a \${CLAUDE_PLUGIN_ROOT}/b\n' >$SKILL/context/old.md" \
  "$SKILL/context/old.md: has 2 occurrence(s)"

run_case "a baselined spoke with fewer hits than listed fails as stale" 1 \
  "printf '%s/context/old.md 3\n' $SKILL >scripts/spoke-plugin-root-baseline.txt" \
  "$SKILL/context/old.md: has 1 occurrence(s)" "lower the count to 1"

run_case "a baseline entry without a count is an environment error" 2 \
  "printf '%s/context/old.md\n' $SKILL >scripts/spoke-plugin-root-baseline.txt" \
  "is not \"<spoke path> <count>\""

run_case "a baseline entry that is not a spoke path is an environment error" 2 \
  "printf 'plugins/alpha/skills/audit/SKILL.md 1\n' >>scripts/spoke-plugin-root-baseline.txt" \
  "is not \"<spoke path> <count>\""

run_case "a missing baseline is an environment error" 2 \
  "rm scripts/spoke-plugin-root-baseline.txt"

# Findings on stderr only; the clean statement on stdout only.
tree=""
if mk_tree tree; then
  # shellcheck disable=SC2016
  printf 'x ${CLAUDE_PLUGIN_ROOT}/y\n' >"$tree/$SKILL/context/fresh.md"
  stdout="$(bash "$tree/scripts/check-spoke-plugin-root.sh" 2>/dev/null)"
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
