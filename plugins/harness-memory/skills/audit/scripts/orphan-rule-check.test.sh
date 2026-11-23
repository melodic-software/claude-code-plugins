#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/orphan-rule-check.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"


rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"


REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
mkdir -p "$REPO/.claude/rules"

printf '# Referenced Rule\n\nbody\n' >"$REPO/.claude/rules/referenced.md"
printf '# Orphan Rule\n\nbody\n' >"$REPO/.claude/rules/orphan.md"
printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# Scoped Rule\n' >"$REPO/.claude/rules/scoped.md"
printf '# Project\n\nSee referenced.md for details.\n' >"$REPO/CLAUDE.md"

(cd "$REPO" && git add -A && git commit -q -m "fixture")


rc=0
OUT=$(cd "$REPO" && bash "$SCRIPT") || rc=$?
assert_exit "report exits 0 (advisory)" 0 "$rc"
assert_contains "flags orphan.md" "$OUT" "orphan.md"
assert_not_contains "does NOT flag referenced.md" "$OUT" "referenced.md"
assert_not_contains "does NOT flag path-scoped scoped.md" "$OUT" "scoped.md"


OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 1" "1" "$OUT"


printf '\nAlso see orphan.md.\n' >>"$REPO/CLAUDE.md"
(cd "$REPO" && git add -A && git commit -q -m "reference orphan")
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 0 after referencing" "0" "$OUT"


OUT=$(cd "$REPO" && bash "$SCRIPT")
assert_contains "clean repo reports no orphans" "$OUT" "No orphan"


FB="$TEST_TMPDIR/fallback"
make_repo "$FB"
mkdir -p "$FB/.claude/rules" "$FB/.work"
printf '# Rule C\n\nbody\n' >"$FB/.claude/rules/c.md"
printf 'see c.md\n' >"$FB/.work/refC.md"
(cd "$FB" && git add -A && git commit -q -m "fallback fixture")

OUT=$(cd "$FB" && bash "$SCRIPT")
assert_contains ".work ref is excluded => c.md orphan" "$OUT" "c.md"


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


SYNC="$TEST_TMPDIR/synced"
make_repo "$SYNC"
mkdir -p "$SYNC/.claude/rules"
printf '# Synced rule\n\nbody\n' >"$SYNC/.claude/rules/synced.md"
(cd "$SYNC" && git add -A && git commit -q -m "chore: sync standards components (#7)")

OUT=$(cd "$SYNC" && bash "$SCRIPT")
assert_contains "a synced orphan is still reported" "$OUT" "synced.md"
assert_contains "a synced orphan carries the upstream route" "$OUT" "synced (commit, upstream: unknown): fix at the sync's source"

report_and_exit
