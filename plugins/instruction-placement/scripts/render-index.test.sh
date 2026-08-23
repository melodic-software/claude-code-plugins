#!/usr/bin/env bash
# Regression tests for render-index.sh (self-contained — no external test lib).
#
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
#
# shellcheck disable=SC2016 # assertions quote markdown code spans; the backticks
# are literal table content, never command substitution.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/render-index.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "must not contain: $3" "$2"; fi
}

run() { bash "$SCRIPT" "$@" 2>&1; }

# A fixture repository carrying a representative mix of instruction surfaces.
build_fixture() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.claude/rules/nested" "$dir/src/billing" "$dir/infra"

  cat >"$dir/.claude/rules/csharp.md" <<'EOF'
---
paths:
  - "**/*.cs"
---

# C# naming conventions

Body.
EOF

  cat >"$dir/.claude/rules/tests.md" <<'EOF'
---
description: "Test layout and the runner to use"
paths: ["**/*.test.ts"]
---

# Tests

Body.
EOF

  cat >"$dir/.claude/rules/always.md" <<'EOF'
# Always loaded

No paths frontmatter, so this rule already loads every session.
EOF

  cat >"$dir/.claude/rules/nested/api.md" <<'EOF'
---
paths:
  - "src/api/**/*.ts"
---

# API rules

Body.
EOF

  printf '# Billing service conventions\n' >"$dir/src/billing/AGENTS.md"
  printf '@AGENTS.md\n' >"$dir/src/billing/CLAUDE.md"
  printf '# Infra is applied by CI only\n' >"$dir/infra/AGENTS.md"
  printf '@AGENTS.md\n\nRoot instructions.\n' >"$dir/CLAUDE.md"
  printf '# Root shared instructions\n' >"$dir/AGENTS.md"

  git -C "$dir" init -q .
  git -C "$dir" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
  printf '%s' "$dir"
}

# --------------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------------
out="$(run --help)"
assert_contains "--help prints usage" "$out" "render-index.sh"

run >/dev/null 2>&1
assert_eq "no arguments is a usage error" "2" "$?"

run bogus >/dev/null 2>&1
assert_eq "unknown subcommand is a usage error" "2" "$?"

run check >/dev/null 2>&1
assert_eq "check without --file is a usage error" "2" "$?"

run write >/dev/null 2>&1
assert_eq "write without --file is a usage error" "2" "$?"

# --------------------------------------------------------------------------
# render — what is indexed and what is deliberately not
# --------------------------------------------------------------------------
repo="$(build_fixture)"
out="$(run render --root "$repo")"

assert_contains "block opens with the begin marker" "$out" "BEGIN GENERATED"
assert_contains "block closes with the end marker" "$out" "END GENERATED"
assert_contains "a path-scoped rule is indexed" "$out" '`.claude/rules/csharp.md`'
assert_contains "its glob is shown" "$out" '`**/*.cs`'
assert_contains "the H1 supplies the topic when no description exists" "$out" "C# naming conventions"
assert_contains "an explicit description wins over the H1" "$out" "Test layout and the runner to use"
assert_contains "a rule in a nested rules directory is indexed" "$out" '`.claude/rules/nested/api.md`'

assert_not_contains "an unscoped rule is NOT indexed" "$out" "always.md"
assert_not_contains "the root CLAUDE.md is NOT indexed" "$out" '| `CLAUDE.md`'
assert_not_contains "the root AGENTS.md is NOT indexed" "$out" '| `AGENTS.md`'

assert_contains "a nested AGENTS.md is indexed" "$out" '`src/billing/AGENTS.md`'
assert_contains "a nested surface is scoped to its subtree" "$out" '`src/billing/**`'
assert_contains "a nested H1 supplies its label" "$out" "Billing service conventions"

# A pure shim carries no content of its own; the file it imports is already
# indexed, so a row for the shim would spend always-loaded budget saying nothing.
assert_not_contains "a pure CLAUDE.md shim is NOT indexed" "$out" '`src/billing/CLAUDE.md`'

# A nested CLAUDE.md that carries its own content beyond the import IS indexed.
mkdir -p "$repo/svc"
{
  printf '@AGENTS.md\n\n'
  printf '# Service specifics\n\n'
  printf 'Claude-only guidance below the import.\n'
} >"$repo/svc/CLAUDE.md"
printf '# Shared service conventions\n' >"$repo/svc/AGENTS.md"
git -C "$repo" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$repo" -c user.email=t@t -c user.name=t commit -qm svc >/dev/null 2>&1
out="$(run render --root "$repo")"
assert_contains "a nested CLAUDE.md with its own content IS indexed" "$out" '`svc/CLAUDE.md`'
assert_contains "its own H1 supplies the label" "$out" "Service specifics"

# An infra dir with only a bare AGENTS.md and no shim: still indexed, because the
# generator reports what exists rather than judging whether it will load.
assert_contains "a shim-less nested AGENTS.md is still listed" "$out" '`infra/AGENTS.md`'

assert_contains "the block explains the subagent gap" "$out" "subagents"
assert_contains "the block explains the compaction behavior" "$out" "compaction"

# --------------------------------------------------------------------------
# Determinism
# --------------------------------------------------------------------------
a="$(run render --root "$repo")"
b="$(run render --root "$repo")"
assert_eq "render is byte-identical across runs" "$a" "$b"

# --------------------------------------------------------------------------
# Empty repository
# --------------------------------------------------------------------------
empty="$(mktemp -d)"
git -C "$empty" init -q .
out="$(run render --root "$empty")"
assert_contains "an empty repo still emits a well-formed block" "$out" "BEGIN GENERATED"
assert_contains "an empty repo says so plainly" "$out" "No path-scoped rules"

# --------------------------------------------------------------------------
# check — in sync, drifted, and missing
# --------------------------------------------------------------------------
target="$repo/AGENTS.md"

run check --file "$target" --root "$repo" >/dev/null 2>&1
assert_eq "check reports 3 when the file has no block" "3" "$?"

run write --file "$target" --root "$repo" >/dev/null 2>&1
assert_eq "write succeeds on a file with no block" "0" "$?"

out="$(run check --file "$target" --root "$repo")"
assert_contains "check reports IN-SYNC right after a write" "$out" "IN-SYNC"
run check --file "$target" --root "$repo" >/dev/null 2>&1
assert_eq "an in-sync check exits 0" "0" "$?"

assert_contains "the written file kept its original content" "$(cat "$target")" "Root shared instructions"

# Adding a rule must drift the committed block.
cat >"$repo/.claude/rules/new.md" <<'EOF'
---
paths:
  - "docs/**/*.md"
---

# Documentation rules
EOF
mkdir -p "$repo/docs" && printf 'x\n' >"$repo/docs/x.md"
git -C "$repo" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$repo" -c user.email=t@t -c user.name=t commit -qm new >/dev/null 2>&1

out="$(run check --file "$target" --root "$repo")"
assert_contains "check detects drift after a rule is added" "$out" "DRIFTED"
run check --file "$target" --root "$repo" >/dev/null 2>&1
assert_eq "a drifted check exits 1" "1" "$?"

run write --file "$target" --root "$repo" >/dev/null 2>&1
out="$(run check --file "$target" --root "$repo")"
assert_contains "rewriting restores sync" "$out" "IN-SYNC"
assert_contains "the new rule appears after the rewrite" "$(cat "$target")" "Documentation rules"

# A rewrite must be idempotent — no duplicated blocks.
run write --file "$target" --root "$repo" >/dev/null 2>&1
run write --file "$target" --root "$repo" >/dev/null 2>&1
marker_count="$(grep -cF "BEGIN GENERATED" "$target")"
assert_eq "repeated writes never duplicate the block" "1" "$marker_count"

# --------------------------------------------------------------------------
# A truncated block is refused rather than guessed at
# --------------------------------------------------------------------------
broken="$repo/BROKEN.md"
{
  printf 'Intro.\n\n'
  printf '%s\n' "<!-- BEGIN GENERATED: instruction-placement rules index -->"
  printf 'orphaned content with no end marker\n'
} >"$broken"

run check --file "$broken" --root "$repo" >/dev/null 2>&1
assert_eq "check refuses a block with no end marker" "3" "$?"

run write --file "$broken" --root "$repo" >/dev/null 2>&1
assert_eq "write refuses a block with no end marker" "1" "$?"
assert_contains "the refused file is left untouched" "$(cat "$broken")" "orphaned content"

# --------------------------------------------------------------------------
# Two begin markers make the block extent ambiguous — refuse, never guess
# --------------------------------------------------------------------------
doubled="$repo/DOUBLED.md"
{
  printf '%s\n' "<!-- BEGIN GENERATED: instruction-placement rules index -->"
  printf 'first\n'
  printf '%s\n' "<!-- END GENERATED: instruction-placement rules index -->"
  printf '%s\n' "<!-- BEGIN GENERATED: instruction-placement rules index -->"
  printf 'second\n'
  printf '%s\n' "<!-- END GENERATED: instruction-placement rules index -->"
} >"$doubled"

out="$(run check --file "$doubled" --root "$repo")"
assert_contains "check names the ambiguity on a doubled block" "$out" "begin markers"
run check --file "$doubled" --root "$repo" >/dev/null 2>&1
assert_eq "check refuses a doubled block with exit 3" "3" "$?"

run write --file "$doubled" --root "$repo" >/dev/null 2>&1
assert_eq "write refuses a doubled block with exit 1" "1" "$?"
assert_contains "the doubled file is left untouched" "$(cat "$doubled")" "second"

# --------------------------------------------------------------------------
# Content outside the block is preserved exactly
# --------------------------------------------------------------------------
preserve="$repo/PRESERVE.md"
{
  printf 'Header line.\n\n'
  printf '%s\n' "<!-- BEGIN GENERATED: instruction-placement rules index -->"
  printf 'stale generated content\n'
  printf '%s\n' "<!-- END GENERATED: instruction-placement rules index -->"
  printf '\nFooter line.\n'
} >"$preserve"

run write --file "$preserve" --root "$repo" >/dev/null 2>&1
content="$(cat "$preserve")"
assert_contains "content before the block survives" "$content" "Header line."
assert_contains "content after the block survives" "$content" "Footer line."
assert_not_contains "stale block content is replaced" "$content" "stale generated content"

# --------------------------------------------------------------------------
# reachable — an index nothing loads is the whole point silently not working
# --------------------------------------------------------------------------
unwired="$(mktemp -d)"
git -C "$unwired" init -q .
printf '# Claude instructions\n\nNo import here.\n' >"$unwired/CLAUDE.md"
printf '# Shared\n' >"$unwired/AGENTS.md"
git -C "$unwired" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$unwired" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1

out="$(run reachable --file "$unwired/AGENTS.md" --root "$unwired")"
assert_contains "reachable reports an unimported AGENTS.md as UNREACHABLE" "$out" "UNREACHABLE"
run reachable --file "$unwired/AGENTS.md" --root "$unwired" >/dev/null 2>&1
assert_eq "an unreachable target exits 1" "1" "$?"

# Writing into an unreachable target still writes, but must say so on stderr:
# the operator may be about to add the import, and silence would hide the fact
# that the index currently does nothing.
# `run` folds stderr into stdout, so the warning needs a direct call that keeps
# the two streams apart.
warn_only() { { bash "$SCRIPT" "$@" >/dev/null; } 2>&1; }

warn="$(warn_only write --file "$unwired/AGENTS.md" --root "$unwired")"
assert_contains "write warns when the index target is unreachable" "$warn" "not imported"
assert_contains "the block is still written" "$(cat "$unwired/AGENTS.md")" "BEGIN GENERATED"

printf '@AGENTS.md\n\n# Claude instructions\n' >"$unwired/CLAUDE.md"
out="$(run reachable --file "$unwired/AGENTS.md" --root "$unwired")"
assert_contains "adding the import makes it reachable" "$out" "LOADED"
warn="$(warn_only write --file "$unwired/AGENTS.md" --root "$unwired")"
assert_eq "no warning once the target is reachable" "" "$warn"

out="$(run reachable --file "$unwired/CLAUDE.md" --root "$unwired")"
assert_contains "a root CLAUDE.md target is always reachable" "$out" "LOADED"

# --------------------------------------------------------------------------
rm -rf "$repo" "$empty"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
