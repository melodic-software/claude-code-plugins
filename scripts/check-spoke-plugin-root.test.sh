#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-spoke-plugin-root.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

SKILL=plugins/alpha/skills/audit

mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label spoke-plugin-root || return 1
  dir="${!1}"
  mkdir -p "$dir/$SKILL/context" "$dir/$SKILL/reference/sub" "$dir/$SKILL/references" "$dir/$SKILL/actions"
  # shellcheck disable=SC2016  # the token is literal fixture text
  {
    printf 'run ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/a.sh\n' >"$dir/$SKILL/context/old.md"
    printf 'run ${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/a.sh\n' >"$dir/$SKILL/SKILL.md"
  }
  printf 'run <skill-dir>/scripts/a.sh\n' >"$dir/$SKILL/context/new.md"
  printf '# spokes that predate the gate\n%s/context/old.md 1  # justified: prose\n' "$SKILL" \
    >"$dir/scripts/spoke-plugin-root-baseline.txt"
}

run_case() { test_harness::check_case mk_tree check-spoke-plugin-root.sh "$@"; }

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
run_case "a spoke under actions/ fails" 1 \
  "printf 'x \${CLAUDE_PLUGIN_ROOT}/y\n' >$SKILL/actions/act.md" \
  "$SKILL/actions/act.md: contains"

# shellcheck disable=SC2016
run_case "a skill-dir token in a reference spoke fails" 1 \
  "printf 'run \${CLAUDE_SKILL_DIR}/scripts/a.sh\n' >$SKILL/reference/r.md" \
  "$SKILL/reference/r.md: contains"

# shellcheck disable=SC2016
run_case "an actions/ spoke baselined at its combined count passes" 0 \
  "printf 'run \${CLAUDE_PLUGIN_ROOT}/a and \${CLAUDE_SKILL_DIR}/b\n' >$SKILL/actions/act.md && printf '%s/actions/act.md 2  # pending: fix\n' $SKILL >>scripts/spoke-plugin-root-baseline.txt"

# shellcheck disable=SC2016
run_case "a skill-dir hit added to a baselined spoke counts toward its total" 1 \
  "printf 'run \${CLAUDE_SKILL_DIR}/b.sh\n' >>$SKILL/context/old.md" \
  "$SKILL/context/old.md: has 2 occurrence(s)" "allows 1"

# shellcheck disable=SC2016
run_case "a token outside the spoke directories is not an offender" 0 \
  "mkdir -p $SKILL/scripts && printf 'x \${CLAUDE_PLUGIN_ROOT}/y\n' >$SKILL/scripts/a.sh"

run_case "a baselined spoke that lost its token fails as stale" 1 \
  "printf 'run <skill-dir>/scripts/a.sh\n' >$SKILL/context/old.md" \
  "$SKILL/context/old.md: scripts/spoke-plugin-root-baseline.txt lists it, but it no longer contains either token"

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
  test_harness::assert_discover_quiet "$tree/scripts/check-spoke-plugin-root.sh"
else
  fail "discover mode: fixture build failed"
fi

test_harness::assert_unknown_mode "$SUT_SRC"

test_harness::report
