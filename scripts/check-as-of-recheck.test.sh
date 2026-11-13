#!/usr/bin/env bash
# Black-box contract test for check-as-of-recheck.sh.
#
# Self-contained and cwd-independent: builds a throwaway tree with fixture
# skill files and a baseline, runs the checker against it, and asserts on exit
# code and output. Mutates only its own mktemp dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-as-of-recheck.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

SKILL=plugins/alpha/skills/audit
BL=scripts/as-of-recheck-baseline.txt
FIXED='add a recheck trigger ("Recheck when: <event>") to this paragraph'

# mk_tree <out-var>: one baselined offender, and a clean file holding each
# passing shape.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label as-of-recheck || return 1
  dir="${!1}"
  mkdir -p "$dir/$SKILL/reference"
  printf 'Intro.\n\nThe limit is 30 (as of 2026-01-01).\n' >"$dir/$SKILL/reference/old.md"
  cat >"$dir/$SKILL/SKILL.md" <<'EOF'
# Audit

The limit is 30 (as of 2026-01-01; recheck when the limits page changes).

The default is 5,
as of
2026-02-02, re-check on the next major release.

As of: 2026-03-03

Recheck when: the article changes.

**As of:** 2026-04-04.

**Recheck:** a new release.

The cap is 9, measured as-of **2026-05-05**:

- **Recheck triggers.** A release note naming the cap.

A pointer with no date: [limits](https://example.com/docs#limits).

```text
as of 2026-06-06 inside a fence is an example, not a record
```
EOF
  printf '# none\n%s/reference/old.md 1  # pending: fix\n' "$SKILL" >"$dir/$BL"
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
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
  out="$(bash "$tree/scripts/check-as-of-recheck.sh" --check 2>&1)"
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

run_case "every passing shape and a baselined offender pass" 0 ":" "1 baselined file(s)"

run_case "a new paragraph with an as-of date and no trigger fails and names the fix" 1 \
  "printf '\nThe timeout is 60 s, as of 2026-01-01.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:" "FIX: $FIXED" "delete the as-of date if it only points at a source"

run_case "the corrected paragraph, with its trigger, passes" 0 \
  "printf '\nThe timeout is 60 s, as of 2026-01-01; recheck when the timeout docs change.\n' >>$SKILL/SKILL.md"

run_case "a trigger two paragraphs on does not cover the date" 1 \
  "printf '\nAs of: 2026-01-01\n\nUnrelated.\n\nRecheck when: later.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:27: FIX:"

run_case "a list item is not covered by the next item when that item carries no trigger" 1 \
  "printf '\n- The cap is 3, as of 2026-01-01.\n- Another fact.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:27: FIX:"

run_case "a table row stands alone" 1 \
  "printf '\n| cap | 3, as of 2026-01-01 |\n| next | recheck when it moves |\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:27: FIX:"

run_case "an agent file is read" 1 \
  "mkdir -p plugins/alpha/agents && printf 'Cap 3 as of 2026-01-01.\n' >plugins/alpha/agents/a.md" \
  "plugins/alpha/agents/a.md:1: FIX:"

run_case "a plugin reference file is read" 1 \
  "mkdir -p plugins/alpha/reference && printf 'Cap 3 As-of 2026-01-01.\n' >plugins/alpha/reference/r.md" \
  "plugins/alpha/reference/r.md:1: FIX:"

run_case "eval samples and fixtures are not read" 0 \
  "mkdir -p $SKILL/evals/c plugins/alpha/skills/audit/scripts/fixtures && printf 'as of 2026-01-01\n' >$SKILL/evals/c/prompt.md && printf 'as of 2026-01-01\n' >$SKILL/scripts/fixtures/f.md"

run_case "a generated copy is reported at its canonical source" 1 \
  "mkdir -p docs/c && printf 'Cap 3 as of 2026-01-01.\n' >docs/c/README.md && cp docs/c/README.md $SKILL/reference/copy.md && printf 'docs/c/README.md %s/reference/copy.md\n' $SKILL >scripts/shared-copies.txt" \
  "docs/c/README.md:1: FIX:"

run_case "a second offender in a baselined file fails and names the counts" 1 \
  "printf '\nAlso 4, as of 2026-01-02.\n' >>$SKILL/reference/old.md" \
  "$SKILL/reference/old.md:5: FIX:" "allows 1 and the file has 2"

run_case "a baselined file with fewer offenders than listed asks for the baseline to shrink" 1 \
  "printf '%s/reference/old.md 2\n' $SKILL >$BL" \
  "lower its count in $BL to 1"

run_case "a baselined file whose offender was fixed asks for its line to go" 1 \
  "printf 'The limit is 30 (as of 2026-01-01; recheck when it moves).\n' >$SKILL/reference/old.md" \
  "$SKILL/reference/old.md: FIX: delete its line from $BL; every as-of date in it now has a recheck trigger"

run_case "a baseline entry naming a missing file fails as stale" 1 \
  "rm $SKILL/reference/old.md" \
  "$SKILL/reference/old.md: FIX: delete its line from $BL; the file does not exist"

run_case "a tree with no plugins passes" 0 "rm -r plugins && : >$BL"

run_case "a baseline entry without a count is an environment error" 2 \
  "printf '%s/reference/old.md\n' $SKILL >$BL" "is not \"<markdown path> <count>\""

run_case "a missing baseline is an environment error" 2 "rm $BL"

# Findings on stderr only; the clean statement on stdout only.
tree=""
if mk_tree tree; then
  printf 'Cap 3 as of 2026-01-01.\n' >"$tree/$SKILL/reference/new.md"
  stdout="$(bash "$tree/scripts/check-as-of-recheck.sh" 2>/dev/null)"
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
