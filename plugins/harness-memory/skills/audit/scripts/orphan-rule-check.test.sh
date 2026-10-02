#!/usr/bin/env bash
# Regression tests for orphan-rule-check.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/orphan-rule-check.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

# --- Case 1: --help exits 0 with usage ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Build a fixture repo with three rules + one referencing surface ---

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
mkdir -p "$REPO/.claude/rules"

# always-loaded (no frontmatter), referenced by CLAUDE.md => NOT orphan
printf '# Referenced Rule\n\nbody\n' >"$REPO/.claude/rules/referenced.md"
# always-loaded (no frontmatter), referenced nowhere => ORPHAN
printf '# Orphan Rule\n\nbody\n' >"$REPO/.claude/rules/orphan.md"
# path-scoped (has paths:), referenced nowhere => EXEMPT (not flagged)
printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# Scoped Rule\n' >"$REPO/.claude/rules/scoped.md"
# referencing surface
printf '# Project\n\nSee referenced.md for details.\n' >"$REPO/CLAUDE.md"

(cd "$REPO" && git add -A && git commit -q -m "fixture")

# --- Case 2: report flags ONLY the orphan ---

rc=0
OUT=$(cd "$REPO" && bash "$SCRIPT") || rc=$?
assert_exit "report exits 0 (advisory)" 0 "$rc"
assert_contains "flags orphan.md" "$OUT" "orphan.md"
assert_not_contains "does NOT flag referenced.md" "$OUT" "referenced.md"
assert_not_contains "does NOT flag path-scoped scoped.md" "$OUT" "scoped.md"

# --- Case 3: --count returns 1 ---

OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 1" "1" "$OUT"

# --- Case 4: once referenced, orphan clears ---

printf '\nAlso see orphan.md.\n' >>"$REPO/CLAUDE.md"
(cd "$REPO" && git add -A && git commit -q -m "reference orphan")
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 0 after referencing" "0" "$OUT"

# --- Case 5: clean repo report message ---

OUT=$(cd "$REPO" && bash "$SCRIPT")
assert_contains "clean repo reports no orphans" "$OUT" "No orphan"

# --- Case 6: the `.work/` memory tier is excluded -------------------------------------

FB="$TEST_TMPDIR/fallback"
make_repo "$FB"
mkdir -p "$FB/.claude/rules" "$FB/.work"
# rule C referenced ONLY from .work/ => ORPHAN (default excludes .work)
printf '# Rule C\n\nbody\n' >"$FB/.claude/rules/c.md"
printf 'see c.md\n' >"$FB/.work/refC.md"
(cd "$FB" && git add -A && git commit -q -m "fallback fixture")

OUT=$(cd "$FB" && bash "$SCRIPT")
assert_contains ".work ref is excluded => c.md orphan" "$OUT" "c.md"

# --- Case 7: a self-describing rule is never an orphan --------------------------------
# The rendered rules index omits unscoped rules, so unreferenced alone proves nothing;
# a `description:` line is the rule naming its own purpose.

DESC="$TEST_TMPDIR/described"
make_repo "$DESC"
mkdir -p "$DESC/.claude/rules"
printf -- '---\ndescription: "House style for prose"\n---\n\n# Described\n\nbody\n' >"$DESC/.claude/rules/described.md"
printf '# Anonymous\n\nbody\n' >"$DESC/.claude/rules/anonymous.md"
printf -- '---\nsomething: else\n---\n\n# Other frontmatter\n\nbody\n' >"$DESC/.claude/rules/other-fm.md"
(cd "$DESC" && git add -A && git commit -q -m "described fixture")

OUT=$(cd "$DESC" && bash "$SCRIPT")
assert_not_contains "a rule with description: frontmatter is not an orphan" "$OUT" "described.md"
assert_contains "a rule with no frontmatter and no reference is an orphan" "$OUT" "anonymous.md"
assert_contains "frontmatter without description: does not exempt" "$OUT" "other-fm.md"
assert_contains "a local orphan carries the local route" "$OUT" "local: add a description: line"
OUT=$(cd "$DESC" && bash "$SCRIPT" --count)
assert_eq "--count == 2 with one self-describing rule" "2" "$OUT"

# --- Case 8: a synced orphan routes its fix upstream ----------------------------------

SYNC="$TEST_TMPDIR/synced"
make_repo "$SYNC"
mkdir -p "$SYNC/.claude/rules"
printf '# Synced rule\n\nbody\n' >"$SYNC/.claude/rules/synced.md"
(cd "$SYNC" && git add -A && git commit -q -m "chore: sync standards components (#7)")

OUT=$(cd "$SYNC" && bash "$SCRIPT")
assert_contains "a synced orphan is still reported" "$OUT" "synced.md"
assert_contains "a synced orphan carries the upstream route" "$OUT" "synced (commit, upstream: unknown): fix at the sync's source"

report_and_exit
