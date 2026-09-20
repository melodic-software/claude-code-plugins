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
SKIPPED=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
# A case this host cannot run is neither a pass nor a failure. It prints its own
# visible line, carries its own counter, and never routes through pass(), so a
# host-blocked proof can never be read off the summary as a case that ran.
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
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

#   commit_all <dir> [<message>]
commit_all() {
  git -C "$1" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm "${2:-t}" >/dev/null 2>&1
}

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

  cat >"$dir/.claude/rules/brace.md" <<'EOF'
---
paths: ["src/*.{ts,tsx}", "lib/**"]
---

# Brace-glob rule

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
  commit_all "$dir"
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

# The glob join pads only the commas it inserts between globs, never a comma
# inside a brace glob (regression: a global comma pad rendered `{ts, tsx}`).
assert_contains "brace-glob commas are not padded, list commas are" "$out" '`src/*.{ts,tsx}, lib/**`'
assert_not_contains "no space is injected inside a brace glob" "$out" '{ts, tsx}'

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
commit_all "$repo" svc
out="$(run render --root "$repo")"
assert_contains "a nested CLAUDE.md with its own content IS indexed" "$out" '`svc/CLAUDE.md`'
assert_contains "its own H1 supplies the label" "$out" "Service specifics"

# An infra dir with only a bare AGENTS.md and no shim: still indexed, because the
# generator reports what exists rather than judging whether it will load.
assert_contains "a shim-less nested AGENTS.md is still listed" "$out" '`infra/AGENTS.md`'

assert_contains "the block states how the trigger behaves in subagents" "$out" "subagents"
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

# `render` prints what a block WOULD say, so a human can see there is nothing to
# index. `write` is the surface that costs context, and an always-loaded block
# saying "there is nothing here" is the cost this index exists to avoid.
printf '# Songs\n\nEverything about this repo.\n' >"$empty/AGENTS.md"
before="$(cat "$empty/AGENTS.md")"
run write --file "$empty/AGENTS.md" --root "$empty" >/dev/null 2>&1
assert_eq "write on a repo with nothing to index exits 0" "0" "$?"
assert_eq "and writes no block into it" "$before" "$(cat "$empty/AGENTS.md")"
out="$(run write --file "$empty/AGENTS.md" --root "$empty")"
assert_contains "and says why it wrote nothing" "$out" "NO-INDEX-NEEDED"

run check --file "$empty/AGENTS.md" --root "$empty" >/dev/null 2>&1
assert_eq "check treats no block and nothing to index as in sync" "0" "$?"
out="$(run check --file "$empty/AGENTS.md" --root "$empty")"
assert_contains "and says so" "$out" "IN-SYNC"

# A block left behind after the last rule went away is drift the writer clears.
{
  printf '# Songs\n\n'
  printf '<!-- BEGIN GENERATED: instruction-placement rules index -->\n'
  printf '\nNo path-scoped rules or nested instruction files are present in this repository.\n\n'
  printf '<!-- END GENERATED: instruction-placement rules index -->\n'
} >"$empty/AGENTS.md"
run check --file "$empty/AGENTS.md" --root "$empty" >/dev/null 2>&1
assert_eq "a block with nothing to index is drift" "1" "$?"
run write --file "$empty/AGENTS.md" --root "$empty" >/dev/null 2>&1
assert_eq "write clears it" "0" "$?"
assert_not_contains "and the block is gone" "$(cat "$empty/AGENTS.md")" "BEGIN GENERATED"
assert_contains "while the surrounding content survives" "$(cat "$empty/AGENTS.md")" "# Songs"
run check --file "$empty/AGENTS.md" --root "$empty" >/dev/null 2>&1
assert_eq "and the repository is in sync afterwards" "0" "$?"

# A relative --file belongs to --root when --root was given. An agent whose
# working directory is not the repository writes `--file AGENTS.md --root <repo>`
# and means the repository's own file; anchoring that to the caller's cwd finds
# nothing and dies.
relroot="$(mktemp -d)"
git -C "$relroot" init -q .
mkdir -p "$relroot/.claude/rules"
printf -- '---\npaths:\n  - "**/*.py"\n---\n# Python\n' >"$relroot/.claude/rules/py.md"
printf '@AGENTS.md\n' >"$relroot/CLAUDE.md"
printf '# Root\n' >"$relroot/AGENTS.md"
commit_all "$relroot"

# Run these from a neutral empty directory. The bug being fixed is a relative
# --file resolving against the CALLER's cwd, so a run of this case against the
# unfixed script writes into whatever repository the suite was launched from.
# It did exactly that once, to this repository's own AGENTS.md.
neutral="$(mktemp -d)"

out="$( (cd "$neutral" && run check --file AGENTS.md --root "$relroot") 2>&1)"
assert_not_contains "a relative --file is resolved against --root, not cwd" "$out" "not a readable file"
(cd "$neutral" && run check --file AGENTS.md --root "$relroot") >/dev/null 2>&1
assert_eq "so the target is found and reported as having no block yet" "3" "$?"
(cd "$neutral" && run write --file AGENTS.md --root "$relroot") >/dev/null 2>&1
assert_eq "write resolves it the same way" "0" "$?"
assert_contains "and the block lands in the repository's file" "$(cat "$relroot/AGENTS.md")" "BEGIN GENERATED"
assert_eq "and nothing was written into the caller's directory" "" "$(ls -A "$neutral")"
(cd "$neutral" && run check --file AGENTS.md --root "$relroot") >/dev/null 2>&1
assert_eq "and check then reads it as in sync" "0" "$?"

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
commit_all "$repo" new

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
# One path-scoped rule, so there is something to index. The subject here is the
# unreachable warning; without a rule the repository would have nothing to index
# and `write` would correctly decline to write a block at all, which is a
# different case (covered above) and would leave this one proving nothing.
mkdir -p "$unwired/.claude/rules"
printf -- '---\npaths:\n  - "**/*.py"\n---\n# Python\n' >"$unwired/.claude/rules/py.md"
commit_all "$unwired"

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

# No root CLAUDE.md anywhere: nothing blocks the session-start walk, so the
# import is not what decides whether the file is read. The verdict is neither
# LOADED nor UNREACHABLE, because whether Claude Code reads AGENTS.md directly
# depends on availability this script cannot observe.
native="$(mktemp -d)"
git -C "$native" init -q .
printf '# Shared\n' >"$native/AGENTS.md"
commit_all "$native"
out="$(run reachable --file "$native/AGENTS.md" --root "$native")"
assert_contains "an AGENTS.md with no CLAUDE.md above it reports NATIVE" "$out" "NATIVE"
assert_not_contains "NATIVE is not UNREACHABLE" "$out" "UNREACHABLE"
run reachable --file "$native/AGENTS.md" --root "$native" >/dev/null 2>&1
assert_eq "a NATIVE target exits 0" "0" "$?"
warn="$(warn_only write --file "$native/AGENTS.md" --root "$native")"
assert_eq "write does not warn about a NATIVE target" "" "$warn"

# The same repo with a root CLAUDE.md that imports nothing: the CLAUDE.md is
# what Claude Code reads, and the AGENTS.md beside it is not read.
printf '# Claude instructions\n\nNo import here.\n' >"$native/CLAUDE.md"
commit_all "$native"
out="$(run reachable --file "$native/AGENTS.md" --root "$native")"
assert_contains "adding a non-importing root CLAUDE.md makes it UNREACHABLE" "$out" "UNREACHABLE"

# --------------------------------------------------------------------------
# wiring — an indexed nested AGENTS.md that no sibling imports never loads
# --------------------------------------------------------------------------
wiring="$(mktemp -d)"
git -C "$wiring" init -q .
mkdir -p "$wiring/shimmed" "$wiring/bare" "$wiring/linked" "$wiring/localonly"
printf '@AGENTS.md\n' >"$wiring/CLAUDE.md"
printf '# Root\n' >"$wiring/AGENTS.md"
printf '# Shimmed\n' >"$wiring/shimmed/AGENTS.md"
printf '@AGENTS.md\n' >"$wiring/shimmed/CLAUDE.md"
printf '# Bare\n' >"$wiring/bare/AGENTS.md"
printf '# Linked\n' >"$wiring/linked/AGENTS.md"
ln -s AGENTS.md "$wiring/linked/CLAUDE.md"
printf '# Local only\n' >"$wiring/localonly/AGENTS.md"
printf '@AGENTS.md\n' >"$wiring/localonly/CLAUDE.local.md"
printf 'CLAUDE.local.md\n' >"$wiring/.gitignore"
commit_all "$wiring"

out="$(run wiring --root "$wiring")"
assert_contains "wiring reports the bare nested AGENTS.md as UNWIRED" "$out" "UNWIRED	bare/AGENTS.md"
assert_contains "wiring reports the shimmed one as WIRED" "$out" "WIRED	shimmed/AGENTS.md"
assert_not_contains "the shimmed one is not UNWIRED" "$out" "UNWIRED	shimmed/AGENTS.md"
assert_contains "a symlinked CLAUDE.md counts as wired" "$out" "WIRED	linked/AGENTS.md"
assert_not_contains "the symlinked one is not UNWIRED" "$out" "UNWIRED	linked/AGENTS.md"
assert_contains "a gitignored CLAUDE.local.md shim counts as wired" "$out" "WIRED	localonly/AGENTS.md"
assert_not_contains "the local-shim one is not UNWIRED" "$out" "UNWIRED	localonly/AGENTS.md"
assert_not_contains "the root AGENTS.md is not a wiring row" "$out" "	AGENTS.md	"
run wiring --root "$wiring" >/dev/null 2>&1
assert_eq "any UNWIRED row exits 1" "1" "$?"

# The index still lists the unwired file (the shim is the fix, not the row's
# removal), and write says so on stderr, once per unwired file.
warn="$(warn_only write --file "$wiring/AGENTS.md" --root "$wiring")"
assert_contains "write warns about the unwired nested AGENTS.md" "$warn" "bare/AGENTS.md is indexed but"
assert_not_contains "write does not warn about the wired one" "$warn" "shimmed/AGENTS.md"
assert_contains "the unwired file keeps its index row" "$(cat "$wiring/AGENTS.md")" '`bare/AGENTS.md`'

printf '@AGENTS.md\n' >"$wiring/bare/CLAUDE.md"
commit_all "$wiring"
out="$(run wiring --root "$wiring")"
assert_not_contains "adding the shim clears the UNWIRED row" "$out" "UNWIRED"
run wiring --root "$wiring" >/dev/null 2>&1
assert_eq "all wired exits 0" "0" "$?"

# No CLAUDE.md anywhere above the nested file: nothing blocks the nested walk,
# so the missing shim is not a defect and the row is not a failure.
nativewiring="$(mktemp -d)"
git -C "$nativewiring" init -q .
mkdir -p "$nativewiring/bare" "$nativewiring/ownclaude"
printf '# Root\n' >"$nativewiring/AGENTS.md"
printf '# Bare\n' >"$nativewiring/bare/AGENTS.md"
printf '# Own\n' >"$nativewiring/ownclaude/AGENTS.md"
printf '# Directory notes, no import\n' >"$nativewiring/ownclaude/CLAUDE.md"
commit_all "$nativewiring"

out="$(run wiring --root "$nativewiring")"
assert_contains "no CLAUDE.md above it makes the bare row NATIVE" "$out" "NATIVE	bare/AGENTS.md"
assert_not_contains "the NATIVE row is not UNWIRED" "$out" "UNWIRED	bare/AGENTS.md"
assert_contains "a non-importing CLAUDE.md in its own directory keeps it UNWIRED" "$out" "UNWIRED	ownclaude/AGENTS.md"
run wiring --root "$nativewiring" >/dev/null 2>&1
assert_eq "a NATIVE row alongside an UNWIRED row still exits 1" "1" "$?"

printf '@AGENTS.md\n' >"$nativewiring/ownclaude/CLAUDE.md"
commit_all "$nativewiring"
run wiring --root "$nativewiring" >/dev/null 2>&1
assert_eq "NATIVE rows alone exit 0" "0" "$?"

# Another tool's directories never reach either surface: not the wiring gate,
# which would demand a Claude shim beside a Cursor file, and not the rendered
# index, which would advertise one as a Claude on-demand surface.
othertools="$(mktemp -d)"
git -C "$othertools" init -q .
mkdir -p "$othertools/.cursor/rules" "$othertools/.codex" "$othertools/.github" "$othertools/src"
printf '@AGENTS.md\n' >"$othertools/CLAUDE.md"
printf '# Root\n' >"$othertools/AGENTS.md"
printf '# Cursor\n' >"$othertools/.cursor/AGENTS.md"
printf '# Cursor rules\n' >"$othertools/.cursor/rules/AGENTS.md"
printf '# Codex\n' >"$othertools/.codex/AGENTS.md"
printf '# Actions\n' >"$othertools/.github/AGENTS.md"
printf '# Src\n' >"$othertools/src/AGENTS.md"
printf '@AGENTS.md\n' >"$othertools/src/CLAUDE.md"
commit_all "$othertools"

out="$(run wiring --root "$othertools")"
assert_not_contains "wiring emits no row for a .cursor tree" "$out" ".cursor"
assert_not_contains "wiring emits no row for a .codex tree" "$out" ".codex"
assert_not_contains "wiring emits no row for a .github tree" "$out" ".github"
assert_contains "wiring still reports an ordinary subtree" "$out" "WIRED	src/AGENTS.md"
run wiring --root "$othertools" >/dev/null 2>&1
assert_eq "another tool's unshimmed AGENTS.md does not fail the gate" "0" "$?"

out="$(run render --root "$othertools")"
assert_not_contains "the index does not list a .cursor file" "$out" '`.cursor'
assert_not_contains "the index does not list a .codex file" "$out" '`.codex'
assert_not_contains "the index does not list a .github file" "$out" '`.github'
assert_contains "the index still lists an ordinary subtree" "$out" '`src/AGENTS.md`'

# `.claude/CLAUDE.md` counts at every level, not only the repository root: the
# memory page counts "a CLAUDE.md, .claude/CLAUDE.md, or CLAUDE.local.md in
# your working directory or any directory above it".
dotclaude="$(mktemp -d)"
git -C "$dotclaude" init -q .
mkdir -p "$dotclaude/svc/.claude"
printf '# Root\n' >"$dotclaude/AGENTS.md"
printf '# Service\n' >"$dotclaude/svc/AGENTS.md"
printf '# Service Claude notes, no import\n' >"$dotclaude/svc/.claude/CLAUDE.md"
commit_all "$dotclaude"

out="$(run wiring --root "$dotclaude")"
assert_contains "a nested .claude/CLAUDE.md blocks the AGENTS.md beside it" "$out" "UNWIRED	svc/AGENTS.md"
run wiring --root "$dotclaude" >/dev/null 2>&1
assert_eq "and that is a gate failure" "1" "$?"

printf '@../AGENTS.md\n' >"$dotclaude/svc/.claude/CLAUDE.md"
commit_all "$dotclaude"
out="$(run wiring --root "$dotclaude")"
assert_not_contains "a nested .claude/CLAUDE.md that imports it wires it" "$out" "UNWIRED"

nonested="$(mktemp -d)"
git -C "$nonested" init -q .
printf '# Root only\n' >"$nonested/CLAUDE.md"
commit_all "$nonested"
out="$(run wiring --root "$nonested")"
assert_eq "no nested AGENTS.md prints no rows" "" "$out"
run wiring --root "$nonested" >/dev/null 2>&1
assert_eq "no nested AGENTS.md exits 0" "0" "$?"

# An import from the root CLAUDE.md, the root .claude/CLAUDE.md, or an ancestor
# directory's CLAUDE.md brings the nested file into context too, so those are
# entry points as well; and the loader follows four hops, not five.
entry="$(mktemp -d)"
git -C "$entry" init -q .
mkdir -p "$entry/.claude" "$entry/byroot" "$entry/bydot" "$entry/anc/leaf" "$entry/five"
printf '@AGENTS.md\n@byroot/AGENTS.md\n' >"$entry/CLAUDE.md"
printf '# Root\n' >"$entry/AGENTS.md"
# A relative import resolves against the importing file's own directory, so the
# root .claude/CLAUDE.md reaches a sibling-of-root tree through `../`.
printf '@../bydot/AGENTS.md\n' >"$entry/.claude/CLAUDE.md"
printf '# By root\n' >"$entry/byroot/AGENTS.md"
printf '# By dot\n' >"$entry/bydot/AGENTS.md"
printf '@leaf/AGENTS.md\n' >"$entry/anc/CLAUDE.md"
printf '# Leaf\n' >"$entry/anc/leaf/AGENTS.md"
printf '@h1.md\n' >"$entry/five/CLAUDE.md"
printf '@h2.md\n' >"$entry/five/h1.md"
printf '@h3.md\n' >"$entry/five/h2.md"
printf '@h4.md\n' >"$entry/five/h3.md"
printf '@AGENTS.md\n' >"$entry/five/h4.md"
printf '# Five\n' >"$entry/five/AGENTS.md"
commit_all "$entry"
out="$(run wiring --root "$entry")"
# `UNWIRED` contains `WIRED`, so a wired assertion is the pair: the row is
# present AND it is not the UNWIRED spelling.
assert_contains "an import from the root CLAUDE.md wires a nested file" "$out" "WIRED	byroot/AGENTS.md"
assert_not_contains "the root-imported file is not UNWIRED" "$out" "UNWIRED	byroot/AGENTS.md"
assert_contains "an import from the root .claude/CLAUDE.md wires a nested file" "$out" "WIRED	bydot/AGENTS.md"
assert_not_contains "the .claude-imported file is not UNWIRED" "$out" "UNWIRED	bydot/AGENTS.md"
assert_contains "an import from an ancestor CLAUDE.md wires a nested file" "$out" "WIRED	anc/leaf/AGENTS.md"
assert_not_contains "the ancestor-imported file is not UNWIRED" "$out" "UNWIRED	anc/leaf/AGENTS.md"
assert_contains "a fifth-hop import does not wire it" "$out" "UNWIRED	five/AGENTS.md"

# --------------------------------------------------------------------------
# Size posture — the index must not become the bloat it exists to remove
# --------------------------------------------------------------------------
many="$(mktemp -d)"
git -C "$many" init -q .
mkdir -p "$many/.claude/rules" "$many/src"
printf 'x\n' >"$many/src/a.cs"
for i in $(seq 1 12); do
  mkdir -p "$many/.claude/rules/group$((i % 3))"
  printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# Rule %s\n' "$i" \
    >"$many/.claude/rules/group$((i % 3))/rule$i.md"
done
commit_all "$many" many

out="$(run render --root "$many")"
rowcount="$(printf '%s\n' "$out" | grep -c '^| `' || true)"
assert_eq "under the cap, every surface is listed individually" "12" "$rowcount"
assert_not_contains "under the cap, no grouping section appears" "$out" "further surface(s)"

out="$(run render --root "$many" --max-rows 5)"
rowcount="$(printf '%s\n' "$out" | grep -c '^| `' || true)"
assert_eq "past the cap, individual rows stop at the cap" "5" "$rowcount"
assert_contains "past the cap, the remainder is counted, not dropped" "$out" "Plus 7 further surface(s)"
assert_contains "the remainder is grouped by location" "$out" "surface(s)"
assert_contains "the reader is told what to do with a grouped tail" "$out" "directly when working inside it"

run render --root "$many" --max-rows abc >/dev/null 2>&1
assert_eq "a non-integer --max-rows is a usage error" "2" "$?"

# --------------------------------------------------------------------------
# Windows path forms: a drive-letter --root and --file round trip
# --------------------------------------------------------------------------
# `git rev-parse --show-toplevel` answers `C:/repo` under Git Bash, and that is
# the spelling hooks/index-drift.sh hands this script on every Windows write.
# Reading such a target as relative made the production check a silent no-op for
# every Windows user, so the round trip is pinned here rather than in the hook.
#
# The probe IS that spelling: where git answers the same string the fixture was
# built under, the host has one path form, there is no second form to drive, and
# the case reports a visible SKIP rather than a pass it never earned.
winrepo="$(build_fixture)"
win_root="$(git -C "$winrepo" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$win_root" || "$win_root" == "$winrepo" ]]; then
  # silent-skip-ok: printed as a visible SKIP line and counted apart from PASS
  skip "a drive-letter --root and --file round trip" \
    "git reports a single path spelling for this checkout"
else
  win_target="$win_root/AGENTS.md"

  out="$(run check --file "$win_target" --root "$win_root")"
  assert_not_contains "a drive-letter --file is absolute, never joined to the cwd" \
    "$out" "not a readable file"
  assert_contains "check reads a drive-letter target" "$out" "NO-BLOCK"

  out="$(run write --file "$win_target" --root "$win_root")"
  assert_contains "write reports the drive-letter target it wrote" "$out" "WROTE"
  assert_not_contains "write does not misreport a drive-letter target as unreachable" \
    "$out" "WARNING"

  out="$(run check --file "$win_target" --root "$win_root")"
  assert_contains "the drive-letter round trip lands in sync" "$out" "IN-SYNC"

  run reachable --file "$win_target" --root "$win_root" >/dev/null 2>&1
  assert_eq "reachable admits a drive-letter target" "0" "$?"

  # The written index must match the one a shell-form run produces byte for
  # byte, so the drive-letter path stays a spelling and never becomes a second
  # result. The two fixtures are built the same way, so only the spelling differs.
  posixrepo="$(build_fixture)"
  run write --file "$posixrepo/AGENTS.md" --root "$posixrepo" >/dev/null 2>&1
  assert_eq "the drive-letter run writes the same index as the shell-form run" \
    "$(cat "$posixrepo/AGENTS.md")" "$(cat "$winrepo/AGENTS.md")"
  rm -rf "$posixrepo"

  # The same drive-letter path spelled with backslashes, as a PowerShell or cmd
  # caller hands it. The renderer re-spells it with forward slashes at intake,
  # so every status line names the forward-slash form; that spelling assertion
  # is the one that pins the normalization. MSYS coreutils already split a
  # backslash path correctly, so the round-trip assertions alone would pass on
  # this host without the fix, and only the spelling assertion discriminates.
  bsrepo="$(build_fixture)"
  bs_root="$(git -C "$bsrepo" rev-parse --show-toplevel 2>/dev/null || true)"
  bs_root_bs="${bs_root//\//\\}"
  bs_target_bs="${bs_root_bs}\\AGENTS.md"

  out="$(run check --file "$bs_target_bs" --root "$bs_root_bs")"
  assert_not_contains "a backslash drive-letter --file is absolute, never joined to the cwd" \
    "$out" "not a readable file"
  assert_contains "check reads a backslash drive-letter target" "$out" "NO-BLOCK"
  assert_contains "check names the backslash target in its forward-slash form" \
    "$out" "$bs_root/AGENTS.md"
  assert_not_contains "check does not echo the backslash spelling" "$out" "$bs_target_bs"

  out="$(run write --file "$bs_target_bs" --root "$bs_root_bs")"
  assert_contains "write reports the backslash drive-letter target it wrote" "$out" "WROTE"
  assert_contains "write names the backslash target in its forward-slash form" \
    "$out" "$bs_root/AGENTS.md"
  assert_not_contains "write does not misreport a backslash drive-letter target as unreachable" \
    "$out" "WARNING"

  out="$(run check --file "$bs_target_bs" --root "$bs_root_bs")"
  assert_contains "the backslash drive-letter round trip lands in sync" "$out" "IN-SYNC"

  run reachable --file "$bs_target_bs" --root "$bs_root_bs" >/dev/null 2>&1
  assert_eq "reachable admits a backslash drive-letter target" "0" "$?"

  assert_eq "the backslash run writes the same index as the forward-slash run" \
    "$(cat "$winrepo/AGENTS.md")" "$(cat "$bsrepo/AGENTS.md")"
  rm -rf "$bsrepo"
fi
rm -rf "$winrepo"

# --------------------------------------------------------------------------
rm -rf "$repo" "$empty"

printf '\n%d case(s), %d failure(s), %d host skip(s)\n' "$CASE_NUM" "$FAILED" "$SKIPPED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
