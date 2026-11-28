#!/usr/bin/env bash
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

run_case() { test_harness::check_case mk_tree check-as-of-recheck.sh "$@"; }

run_case "every passing shape and a baselined offender pass" 0 ":" "1 baselined file(s)"

run_case "a new paragraph with an as-of date and no trigger fails and names the fix" 1 \
  "printf '\nThe timeout is 60 s, as of 2026-01-01.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:" "FIX: $FIXED" "delete the as-of date if it only points at a source"

run_case "the corrected paragraph, with its trigger, passes" 0 \
  "printf '\nThe timeout is 60 s, as of 2026-01-01; recheck when the timeout docs change.\n' >>$SKILL/SKILL.md"

run_case "a **As of**: stamp with no trigger fails" 1 \
  "printf '\n**As of**: 2026-01-01\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:27: FIX:"

run_case "a **As of**: stamp with its **Recheck trigger**: in the paragraph passes" 0 \
  "printf '\n**As of**: 2026-01-01. **Recheck trigger**: the limits page changes.\n' >>$SKILL/SKILL.md"

run_case "a **As of**: item followed by a **Recheck trigger**: item passes" 0 \
  "printf '\n- **As of**: 2026-01-01\n- **Recheck trigger**: the limits page changes.\n' >>$SKILL/SKILL.md"

run_case "a trigger two paragraphs on does not cover the date" 1 \
  "printf '\nAs of: 2026-01-01\n\nUnrelated.\n\nRecheck when: later.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:27: FIX:"

run_case "a list item is not covered by the next item when that item carries no trigger" 1 \
  "printf '\n- The cap is 3, as of 2026-01-01.\n- Another fact.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:27: FIX:"

run_case "a fence closes only on its own opener, so a nested example stays skipped" 0 \
  "printf '\n%s\n%s\n# as of 2026-01-01\n%s\nas of 2026-01-02\n%s\n' '\`\`\`\`markdown' '\`\`\`bash' '\`\`\`' '\`\`\`\`' >>$SKILL/SKILL.md"

run_case "a tilde fence is not closed by backticks" 0 \
  "printf '\n~~~text\n\`\`\`\nas of 2026-01-01\n~~~\n' >>$SKILL/SKILL.md"

run_case "text after a closed fence is read again" 1 \
  "printf '\n\`\`\`\`\nx\n\`\`\`\`\n\nCap 3, as of 2026-01-01.\n' >>$SKILL/SKILL.md" \
  "$SKILL/SKILL.md:31: FIX:"

run_case "a wrapped line opening with an issue reference carries the trigger" 0 \
  "printf '\nThe cap is 3, as of 2026-01-01, per\n#15663; recheck when the cap moves.\n' >>$SKILL/SKILL.md"

run_case "a wrapped line opening with an issue reference carries the date" 0 \
  "printf '\nThe cap is 3; recheck when it moves, per\n#15663, as of 2026-01-01.\n' >>$SKILL/SKILL.md"

run_case "a heading still stands alone" 1 \
  "printf '\n# Cap 3 as of 2026-01-01\nIt moves; recheck when it does, in the body below the heading.\n' >>$SKILL/SKILL.md" \
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

run_case "a docs/upstream record is not read" 0 \
  "mkdir -p docs/upstream && printf '**As of**: 2026-01-01\n' >docs/upstream/u.md"

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

tree=""
if mk_tree tree; then
  printf 'Cap 3 as of 2026-01-01.\n' >"$tree/$SKILL/reference/new.md"
  test_harness::assert_discover_quiet "$tree/scripts/check-as-of-recheck.sh"
else
  fail "discover mode: fixture build failed"
fi

test_harness::assert_unknown_mode "$SUT_SRC"

test_harness::report
