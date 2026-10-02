#!/usr/bin/env bash
# Self-contained tests for check-effort-pins.sh (no external test lib; ships with the plugin).
#
# Every page variant is derived from fixtures/effort-pins in a temp dir and read
# through the SETTINGS_AUDIT_DOCS_FIXTURE_DIR seam, so no case touches the network.
#
# Backticked markdown must reach the files unexpanded, so single quotes are the
# correct spelling.
# shellcheck disable=SC2016
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-effort-pins.sh"
FX="$SCRIPT_DIR/fixtures/effort-pins"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
count() { grep -c -- "$2" <<<"$1"; }

# variant <name> <sed script>: a fixture dir whose page is the shipped page run
# through <sed script>. A script that edits nothing fails the suite, so no case
# passes against the unchanged page by accident.
variant() {
  mkdir -p "$T/v-$1"
  cp "$FX/llms.txt" "$T/v-$1/llms.txt"
  sed -e "$2" "$FX/model-config.md" >"$T/v-$1/model-config.md"
  # Callers run this in a command substitution, so a no-op is recorded in a file.
  cmp -s "$FX/model-config.md" "$T/v-$1/model-config.md" && printf '%s\n' "$1" >>"$T/noop-variants"
  printf '%s' "$T/v-$1"
}

# run <fixture dir> <args...>: OUT is stdout, ERR stderr, RC the exit code.
run() {
  local fx="$1"
  shift
  RC=0
  OUT="$(SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$fx" bash "$SCRIPT" "$@" 2>"$T/stderr")" || RC=$?
  ERR="$(cat "$T/stderr")"
}

# A scan root holding every pin kind. The no-effort agent carries `effort:` in its
# body only, which is not frontmatter and so not a pin.
ROOT="$T/root"
mkdir -p "$ROOT/plugins/p1/agents" "$ROOT/plugins/p1/skills/s1/context" \
  "$ROOT/plugins/harness-ops/skills/lanes/context" "$ROOT/prompts/loops"
printf '%s\n' '---' 'name: a-high' 'effort: high' '---' 'Body.' >"$ROOT/plugins/p1/agents/a-high.md"
printf '%s\n' '---' 'name: a-medium' 'effort: "medium"' '---' 'Body.' >"$ROOT/plugins/p1/agents/a-medium.md"
printf '%s\n' '---' 'name: a-none' '---' 'effort: high' >"$ROOT/plugins/p1/agents/a-none.md"
printf '%s\n' '---' 'name: s1' 'effort: high' '---' 'Body.' >"$ROOT/plugins/p1/skills/s1/SKILL.md"
printf '%s\n' '```json' '{ "lanes": [' '  { "name": "one", "effort": "high" },' '  { "name": "two", "effort": "medium" }' '] }' '```' \
  >"$ROOT/plugins/harness-ops/skills/lanes/context/config.md"
printf '%s\n' 'Pass `--effort` on every lane.' '' '```bash' 'claude --model opus --effort high' '```' \
  >"$ROOT/prompts/loops/loop-lane-prompts.md"
printf '%s\n' '```js' "agent({ prompt: 'x', effort: 'high' })" '```' >"$ROOT/plugins/p1/skills/s1/context/flow.md"

BOGUS="$T/bogus"
cp -R "$ROOT" "$BOGUS"
printf '%s\n' '---' 'name: a-bogus' 'effort: turbo' '---' >"$BOGUS/plugins/p1/agents/a-bogus.md"
EMPTY="$T/empty"
mkdir -p "$EMPTY"

tree_hash() { (cd "$T" && find root bogus empty -type f | sort | xargs sha256sum | sha256sum); }
fixture_hash() { (cd "$FX" && find . -type f | sort | xargs sha256sum | sha256sum); }
TREE_BEFORE="$(tree_hash)"
FX_BEFORE="$(fixture_hash)"

# --- help -------------------------------------------------------------------
RC=0
OUT="$(bash "$SCRIPT" --help)" || RC=$?
assert_eq "help: exits 0" 0 "$RC"
assert_contains "help: prints usage" "$OUT" "Usage:"

# --- print-baseline round trip --------------------------------------------------
run "$FX" --print-baseline --root "$EMPTY"
assert_eq "print-baseline: exits 0" 0 "$RC"
if [[ "$OUT" =~ ^sha256=[0-9a-f]{64}\ levels=low,medium,high,xhigh,max\ as_of=[0-9]{4}-[0-9]{2}-[0-9]{2}\ source=https://code.claude.com/docs/en/model-config$ ]]; then
  pass "print-baseline: one line, hash, the five fixture levels, date and source"
else
  fail "print-baseline: one line, hash, the five fixture levels, date and source" "$OUT"
fi
BASE="$T/fixture.baseline"
printf '%s\n' "$OUT" >"$BASE"
assert_not_contains "print-baseline: no row text in the baseline" "$(cat "$BASE")" "socks"

# --- unchanged table: every pin kind is listed and ok -----------------------------
run "$FX" --baseline "$BASE" --root "$ROOT"
assert_eq "unchanged table: exits 0" 0 "$RC"
assert_contains "unchanged table: table line is same" "$OUT" "table status=same levels=low,medium,high,xhigh,max"
assert_contains "pin kind frontmatter: agent" "$OUT" "pin path=plugins/p1/agents/a-high.md kind=frontmatter effort=high status=ok reason=none"
assert_contains "pin kind frontmatter: quoted value unquoted" "$OUT" "pin path=plugins/p1/agents/a-medium.md kind=frontmatter effort=medium status=ok reason=none"
assert_contains "pin kind frontmatter: skill" "$OUT" "pin path=plugins/p1/skills/s1/SKILL.md kind=frontmatter effort=high status=ok"
assert_contains "pin kind lane-config: first lane" "$OUT" "pin path=plugins/harness-ops/skills/lanes/context/config.md kind=lane-config effort=high status=ok"
assert_contains "pin kind lane-config: second lane" "$OUT" "kind=lane-config effort=medium status=ok"
assert_contains "pin kind lane-launch" "$OUT" "pin path=prompts/loops/loop-lane-prompts.md kind=lane-launch effort=high status=ok"
assert_contains "pin kind workflow-literal" "$OUT" "pin path=plugins/p1/skills/s1/context/flow.md kind=workflow-literal effort=high status=ok"
assert_not_contains "no effort in frontmatter: not a pin" "$OUT" "a-none.md"
assert_contains "unchanged table: summary" "$OUT" "summary pins=7 drift=0 status=ok"

# --- backticked-cell: level cells are read without their backticks ---------------
assert_not_contains "backticked-cell: levels carry no backtick" "$(grep '^table ' <<<"$OUT")" '`'
variant plain 's/`//g' >/dev/null
run "$T/v-plain" --print-baseline --root "$EMPTY"
assert_contains "backticked-cell: the same level set with or without backticks" "$OUT" "levels=low,medium,high,xhigh,max "

# --- text outside the three hashed parts does not move the hash ------------------
run "$(variant prose 's/Paragraph about picking a dial position./Other words entirely./; s/A pretend toggle that is not a level/Reworded toggle/')" \
  --baseline "$BASE" --root "$ROOT"
assert_eq "unhashed text and a non-level row edited: exits 0" 0 "$RC"
assert_contains "unhashed text and a non-level row edited: same" "$OUT" "table status=same"

# A heading inside a fenced block is not a heading.
run "$(variant fenced '/^# Synthetic model page/a\
\
```text\
#### Choose an effort level\
| Level | When to use it |\
| :- | :- |\
| `low` | Fenced row |\
```')" --baseline "$BASE" --root "$ROOT"
assert_eq "fenced heading ignored: exits 0" 0 "$RC"
assert_contains "fenced heading ignored: same" "$OUT" "table status=same"

# --- changed-table: a level row changed ------------------------------------------
run "$(variant changed 's/Tuning a piano with a friend listening/Tuning a harp alone/')" --baseline "$BASE" --root "$ROOT"
assert_eq "changed-table: exits 1" 1 "$RC"
assert_contains "changed-table: table line is changed" "$OUT" "table status=changed"
assert_eq "changed-table: every pin flagged table-changed" 7 "$(count "$OUT" 'reason=table-changed')"
assert_eq "changed-table: no pin left ok" 0 "$(count "$OUT" 'status=ok')"
assert_contains "changed-table: summary" "$OUT" "summary pins=7 drift=7 status=drift"

# A model row of the Levels table changed.
run "$(variant levels 's/^| Model Gamma | `low`, `medium`, `high`, `max` |$/| Model Gamma | `low`, `medium`, `high`, `xhigh`, `max` |/')" \
  --baseline "$BASE" --root "$ROOT"
assert_eq "changed-table, Levels row: exits 1" 1 "$RC"
assert_contains "changed-table, Levels row: changed" "$OUT" "table status=changed"

# --- changed-defaults: item 3 of the resolution list changed -----------------------
run "$(variant defaults 's/Model Gamma at `low`/Model Gamma at `high`/')" --baseline "$BASE" --root "$ROOT"
assert_eq "changed-defaults: exits 1" 1 "$RC"
assert_contains "changed-defaults: table line is changed" "$OUT" "table status=changed"
assert_eq "changed-defaults: every pin flagged table-changed" 7 "$(count "$OUT" 'reason=table-changed')"
run "$(variant item4 's/a coin toss/a dice roll/')" --baseline "$BASE" --root "$ROOT"
assert_contains "changed-defaults: another list item is not hashed" "$OUT" "table status=same"

# --- failed-fetch: the page cannot be read ---------------------------------------
mkdir -p "$T/v-noindex"
printf '%s\n' '# Synthetic docs index' '- [Other](https://code.claude.com/docs/en/other.md): other' >"$T/v-noindex/llms.txt"
cp "$FX/model-config.md" "$T/v-noindex/model-config.md"
run "$T/v-noindex" --baseline "$BASE" --root "$ROOT"
assert_eq "failed-fetch, slug not in index: exits 3" 3 "$RC"
assert_contains "failed-fetch, slug not in index: unread with the reason" "$OUT" "table status=unread"
assert_contains "failed-fetch, slug not in index: reason named" "$OUT" "reason=not-in-index"
assert_eq "failed-fetch, slug not in index: no pin line" 0 "$(count "$OUT" '^pin ')"
assert_contains "failed-fetch, slug not in index: no claim" "$OUT" "status=no-claim"
mkdir -p "$T/v-nopage"
cp "$FX/llms.txt" "$T/v-nopage/llms.txt"
run "$T/v-nopage" --baseline "$BASE" --root "$ROOT"
assert_eq "failed-fetch, page missing: exits 3" 3 "$RC"
assert_contains "failed-fetch, page missing: unread" "$OUT" "table status=unread"
run "$T/v-nopage" --print-baseline --root "$EMPTY"
assert_eq "failed-fetch, print-baseline: exits 3" 3 "$RC"
assert_eq "failed-fetch, print-baseline: prints no baseline" "" "$OUT"

# --- reshaped page ---------------------------------------------------------------
run "$(variant reshaped 's/^#### Choose an effort level$/#### Pick a dial position/')" --baseline "$BASE" --root "$ROOT"
assert_eq "reshaped, Choose heading renamed: exits 3" 3 "$RC"
assert_contains "reshaped, Choose heading renamed: unparsed" "$OUT" "table status=unparsed"
assert_contains "reshaped, Choose heading renamed: reason" "$OUT" "reason=no-choose-heading"
assert_eq "reshaped, Choose heading renamed: no pin line" 0 "$(count "$OUT" '^pin ')"
run "$(variant noitem3 '/^3\. /d')" --baseline "$BASE" --root "$ROOT"
assert_eq "reshaped, no item 3: exits 3" 3 "$RC"
assert_contains "reshaped, no item 3: reason" "$OUT" "reason=no-defaults-item"
run "$(variant nocol 's/^| Model | Levels |$/| Model | Options |/')" --baseline "$BASE" --root "$ROOT"
assert_eq "reshaped, Levels column renamed: exits 3" 3 "$RC"
assert_contains "reshaped, Levels column renamed: reason" "$OUT" "reason=no-levels-column"

# --- a pin whose level is not in the table ------------------------------------------
run "$FX" --baseline "$BASE" --root "$BOGUS"
assert_eq "level not in table: exits 1" 1 "$RC"
assert_contains "level not in table: flagged" "$OUT" "pin path=plugins/p1/agents/a-bogus.md kind=frontmatter effort=turbo status=drift reason=level-not-in-table"
assert_contains "level not in table: the others stay ok" "$OUT" "summary pins=8 drift=1 status=drift"
run "$T/v-changed" --baseline "$BASE" --root "$BOGUS"
assert_contains "level not in table: wins over table-changed" "$OUT" "effort=turbo status=drift reason=level-not-in-table"

# --- no pins ----------------------------------------------------------------------
run "$FX" --baseline "$BASE" --root "$EMPTY"
assert_eq "no pins: exits 0" 0 "$RC"
assert_contains "no pins: summary" "$OUT" "summary pins=0 drift=0 status=ok"

# --- --docs-dir reads the page from disk, with no fetcher ---------------------------
RC=0
OUT="$(CLAUDE_PLUGIN_ROOT="$T/no-plugin" SETTINGS_AUDIT_DOCS_FIXTURE_DIR='' bash "$SCRIPT" --docs-dir "$FX" --baseline "$BASE" --root "$ROOT" 2>&1)" || RC=$?
assert_eq "docs-dir: the on-disk page is used without the fetcher" 0 "$RC"
assert_contains "docs-dir: same" "$OUT" "table status=same"

# --- fatal ------------------------------------------------------------------------
run "$FX" --baseline "$T/absent.baseline" --root "$ROOT"
assert_eq "missing baseline: exits 2" 2 "$RC"
assert_contains "missing baseline: named" "$ERR" "baseline not found"
printf 'levels=low\n' >"$T/bad.baseline"
run "$FX" --baseline "$T/bad.baseline" --root "$ROOT"
assert_eq "malformed baseline: exits 2" 2 "$RC"
run "$FX" --nope
assert_eq "unknown argument: exits 2" 2 "$RC"
RC=0
OUT="$(CLAUDE_PLUGIN_ROOT="$T/no-plugin" SETTINGS_AUDIT_DOCS_FIXTURE_DIR="$FX" bash "$SCRIPT" --baseline "$BASE" --root "$ROOT" 2>&1)" || RC=$?
assert_eq "missing fetcher: exits 2" 2 "$RC"
assert_contains "missing fetcher: named" "$OUT" "shared fetcher not found"

assert_eq "every page variant edits the page" "" "$(cat "$T/noop-variants" 2>/dev/null)"

# --- no scanned file changed --------------------------------------------------------
assert_eq "byte-identical: no scan-root file changed across every case" "$TREE_BEFORE" "$(tree_hash)"
assert_eq "byte-identical: no fixture file changed across every case" "$FX_BEFORE" "$(fixture_hash)"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
