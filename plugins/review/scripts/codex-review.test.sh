#!/usr/bin/env bash
# Regression tests for codex-review.sh (self-contained, offline, ships with the plugin).
#
# A stub claude CLI prints a fixture `plugin list --json`, and a stub codex plugin's
# scripts/codex-companion.mjs answers `setup --json` from environment variables and prints a
# finding for `review`, so no real Codex CLI or login is touched.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/codex-review.sh"

if ! command -v node >/dev/null 2>&1; then
  printf 'SKIP: node not found; codex-review.sh needs it\n'
  exit 0
fi

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: [$3], actual: [$2]" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected not to contain: [$3], actual: [$2]" ;;
  *) pass "$1" ;;
  esac
}

# The stub codex plugin. Its review records its argv in $FAKE_REVIEW_LOG so a case can tell
# whether review ran and which base it got.
PLUGIN="$TEST_TMPDIR/codex-plugin"
mkdir -p "$PLUGIN/scripts"
cat >"$PLUGIN/scripts/codex-companion.mjs" <<'EOF'
import { appendFileSync } from "node:fs";
const [sub, ...rest] = process.argv.slice(2);
if (sub === "setup") {
  process.stdout.write(JSON.stringify({
    ready: process.env.FAKE_CODEX_AVAILABLE === "1" && process.env.FAKE_CODEX_LOGGED_IN === "1",
    codex: { available: process.env.FAKE_CODEX_AVAILABLE === "1" },
    auth: { loggedIn: process.env.FAKE_CODEX_LOGGED_IN === "1" },
    actionsTaken: [],
  }));
} else if (sub === "review" || sub === "adversarial-review") {
  appendFileSync(process.env.FAKE_REVIEW_LOG, `${sub} ${rest.join(" ")}\n`);
  if (process.env.FAKE_REVIEW_EXIT && process.env.FAKE_REVIEW_EXIT !== "0") {
    process.stderr.write("Codex review failed: turn aborted\n");
    process.exit(Number(process.env.FAKE_REVIEW_EXIT));
  }
  process.stdout.write("[P1] src/stock.js:12 reserve() checks then awaits, so two checkouts both pass\n");
}
EOF

# The stub claude CLI prints $FAKE_PLUGIN_LIST for `plugin list --json`.
STUB_CLAUDE="$TEST_TMPDIR/claude"
cat >"$STUB_CLAUDE" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "plugin list --json" ]] || exit 1
cat "$FAKE_PLUGIN_LIST"
EOF
chmod +x "$STUB_CLAUDE"

LIST_INSTALLED="$TEST_TMPDIR/installed.json"
printf '[{"id":"other@market","version":"1.0.0","scope":"user","enabled":true,"installPath":"/nowhere"},{"id":"codex@openai-codex","version":"1.0.6","scope":"user","enabled":true,"installPath":"%s"}]' "$PLUGIN" >"$LIST_INSTALLED"
LIST_IN_PLACE="$TEST_TMPDIR/in-place.json"
printf '[{"id":"codex@openai-codex","version":"1.0.6","scope":"user","enabled":true,"installPath":"/nowhere","readFromFolder":"%s"}]' "$PLUGIN" >"$LIST_IN_PLACE"
LIST_DISABLED="$TEST_TMPDIR/disabled.json"
printf '[{"id":"codex@openai-codex","version":"1.0.6","scope":"user","enabled":false,"installPath":"%s"}]' "$PLUGIN" >"$LIST_DISABLED"
LIST_ABSENT="$TEST_TMPDIR/absent.json"
printf '[{"id":"other@market","version":"1.0.0","scope":"user","enabled":true,"installPath":"/nowhere"}]' >"$LIST_ABSENT"
LIST_NO_COMPANION="$TEST_TMPDIR/no-companion.json"
mkdir -p "$TEST_TMPDIR/empty-plugin"
printf '[{"id":"codex@openai-codex","version":"1.0.6","scope":"user","enabled":true,"installPath":"%s"}]' "$TEST_TMPDIR/empty-plugin" >"$LIST_NO_COMPANION"

# run_case <plugin-list> <available> <logged-in> [args...]: sets OUT, RC and REVIEW_LOG. A caller's
# FAKE_REVIEW_EXIT sets the stub review's exit code.
run_case() {
  local list="$1" available="$2" logged_in="$3"
  shift 3
  REVIEW_LOG="$TEST_TMPDIR/review-$CASE_NUM-$RANDOM.log"
  : >"$REVIEW_LOG"
  RC=0
  OUT=$(FANOUT_CODEX_CLAUDE_BIN="$STUB_CLAUDE" FAKE_PLUGIN_LIST="$list" \
    FAKE_CODEX_AVAILABLE="$available" FAKE_CODEX_LOGGED_IN="$logged_in" \
    FAKE_REVIEW_LOG="$REVIEW_LOG" FAKE_REVIEW_EXIT="${FAKE_REVIEW_EXIT:-0}" \
    bash "$SCRIPT" "$@") || RC=$?
}

# --- Usage ---
RC=0
OUT=$(bash "$SCRIPT" --help) || RC=$?
assert_eq "--help exits 0" 0 "$RC"
assert_contains "--help prints usage" "$OUT" "Usage:"

RC=0
bash "$SCRIPT" >/dev/null 2>&1 || RC=$?
assert_eq "no --base is a usage error" 2 "$RC"

RC=0
bash "$SCRIPT" --base --adversarial >/dev/null 2>&1 || RC=$?
assert_eq "--base followed by a flag is a usage error" 2 "$RC"

# --- No claude CLI: skipped, never ran ---
RC=0
OUT=$(FANOUT_CODEX_CLAUDE_BIN="$TEST_TMPDIR/no-such-claude" bash "$SCRIPT" --base origin/main) || RC=$?
assert_eq "no claude CLI exits 0" 0 "$RC"
assert_contains "no claude CLI reports skipped" "$OUT" "codex: skipped (claude CLI not found"

# --- Plugin absent or disabled ---
run_case "$LIST_ABSENT" 1 1 --base origin/main
assert_contains "plugin not installed reports skipped" "$OUT" "codex: skipped (codex@openai-codex is not installed or not enabled)"
assert_eq "plugin not installed never runs review" "" "$(cat "$REVIEW_LOG")"

run_case "$LIST_DISABLED" 1 1 --base origin/main
assert_contains "plugin disabled reports skipped" "$OUT" "codex: skipped (codex@openai-codex is not installed or not enabled)"

run_case "$LIST_NO_COMPANION" 1 1 --base origin/main
assert_contains "missing companion reports skipped" "$OUT" "codex: skipped (codex companion runtime not found"

LIST_GARBLED="$TEST_TMPDIR/garbled.json"
printf 'not json' >"$LIST_GARBLED"
run_case "$LIST_GARBLED" 1 1 --base origin/main
assert_eq "unreadable plugin list reports skipped" "codex: skipped (claude plugin list --json gave no readable list)" "$OUT"

# --- No Codex CLI: skipped, never ran ---
run_case "$LIST_INSTALLED" 0 0 --base origin/main
assert_eq "no Codex CLI exits 0" 0 "$RC"
assert_eq "no Codex CLI reports skipped" "codex: skipped (Codex CLI not installed)" "$OUT"
assert_not_contains "no Codex CLI never reports ran" "$OUT" "codex: ran"
assert_eq "no Codex CLI never runs review" "" "$(cat "$REVIEW_LOG")"

# --- Codex CLI present but not logged in: skipped ---
run_case "$LIST_INSTALLED" 1 0 --base origin/main
assert_eq "no login reports skipped" "codex: skipped (Codex CLI not logged in)" "$OUT"
assert_eq "no login never runs review" "" "$(cat "$REVIEW_LOG")"

# --- Ready: ran, with the findings and the base passed through ---
run_case "$LIST_INSTALLED" 1 1 --base origin/trunk
assert_eq "ready exits 0" 0 "$RC"
assert_eq "ready reports ran first" "codex: ran" "$(printf '%s\n' "$OUT" | head -n 1)"
assert_contains "ready lists Codex findings" "$OUT" "[P1] src/stock.js:12 reserve() checks then awaits"
assert_eq "ready passes the review base through" "review --wait --base origin/trunk" "$(cat "$REVIEW_LOG")"

run_case "$LIST_IN_PLACE" 1 1 --base origin/main
assert_eq "in-place plugin uses readFromFolder" "codex: ran" "$(printf '%s\n' "$OUT" | head -n 1)"

run_case "$LIST_INSTALLED" 1 1 --base origin/main --adversarial
assert_eq "--adversarial runs adversarial-review" "adversarial-review --wait --base origin/main" "$(cat "$REVIEW_LOG")"

# --- Model and brief: native review commands only, never task, never --write ---
run_case "$LIST_INSTALLED" 1 1 --base origin/main --model gpt-x
assert_eq "--model reaches review" "review --wait --base origin/main --model gpt-x" "$(cat "$REVIEW_LOG")"

BRIEF="$TEST_TMPDIR/brief.md"
printf -- '--look for races in reserve()' >"$BRIEF"
run_case "$LIST_INSTALLED" 1 1 --base origin/main --model gpt-x --brief-file "$BRIEF"
assert_eq "--brief-file runs adversarial-review with the brief as focus text after --" \
  "adversarial-review --wait --base origin/main --model gpt-x -- --look for races in reserve()" "$(cat "$REVIEW_LOG")"
assert_eq "--brief-file keeps the first status line" "codex: ran" "$(printf '%s\n' "$OUT" | head -n 1)"

for args in "--base origin/main" "--base origin/main --adversarial" "--base origin/main --model gpt-x --brief-file $BRIEF"; do
  # shellcheck disable=SC2086 # the word list is the argument vector under test
  run_case "$LIST_INSTALLED" 1 1 $args
  assert_not_contains "no task run for: $args" "$(cat "$REVIEW_LOG")" "task"
  assert_not_contains "no --write for: $args" "$(cat "$REVIEW_LOG")" "--write"
done

RC=0
bash "$SCRIPT" --base origin/main --model 'bad model' >/dev/null 2>&1 || RC=$?
assert_eq "a model name with a space is a usage error" 2 "$RC"
RC=0
bash "$SCRIPT" --base origin/main --brief-file "$TEST_TMPDIR/no-such-brief" >/dev/null 2>&1 || RC=$?
assert_eq "a missing brief file is a usage error" 2 "$RC"

# --- Review started and failed: failed, not ran or skipped ---
FAKE_REVIEW_EXIT=3 run_case "$LIST_INSTALLED" 1 1 --base origin/main
assert_eq "failed review exits 0" 0 "$RC"
assert_eq "failed review reports failed" "codex: failed (review exited 3: Codex review failed: turn aborted)" "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
