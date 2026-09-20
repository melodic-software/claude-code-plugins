#!/usr/bin/env bash
# Regression tests for nested-agents-check.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/nested-agents-check.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

# Local assert_contains: the detail line also names the haystack.
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 in: $2" ;;
  esac
}

commit_all() {
  (cd "$1" && git add -A && git commit -q -m "${2:-fixture}")
}

# --- Case 1: --help, bad argument, outside a repo ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
rc=0
bash "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "a bad argument exits 2" 2 "$rc"
NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
rc=0
(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT") >/dev/null 2>&1 || rc=$?
assert_eq "outside a git repo exits 1" 1 "$rc"

# --- Case 2: the mix this check exists for ---

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
mkdir -p "$REPO/shimmed" "$REPO/bare" "$REPO/linked" "$REPO/localonly" "$REPO/deep/a/b" "$REPO/vendor/x" "$REPO/node_modules/y"
printf 'root agents\n' >"$REPO/AGENTS.md" # root-level: not examined
# The root CLAUDE.md is what makes an unshimmed nested AGENTS.md a finding: with
# a CLAUDE.md in the working directory or above it, Claude Code reads CLAUDE.md
# files and never attaches a bare nested AGENTS.md.
printf '@AGENTS.md\n' >"$REPO/CLAUDE.md"
printf 'shimmed\n' >"$REPO/shimmed/AGENTS.md"
printf '@AGENTS.md\n' >"$REPO/shimmed/CLAUDE.md" # wired by import
printf 'bare\n' >"$REPO/bare/AGENTS.md"          # UNWIRED
printf 'linked\n' >"$REPO/linked/AGENTS.md"
ln -s AGENTS.md "$REPO/linked/CLAUDE.md" # wired by symlink
printf 'localonly\n' >"$REPO/localonly/AGENTS.md"
printf '@AGENTS.md\n' >"$REPO/localonly/CLAUDE.local.md" # wired by a gitignored local file
printf 'CLAUDE.local.md\n' >"$REPO/.gitignore"
printf 'deep\n' >"$REPO/deep/a/b/AGENTS.md"
printf '# Notes\n\nSee @hub.md for the rest.\n' >"$REPO/deep/a/b/CLAUDE.md"
printf '@AGENTS.md\n' >"$REPO/deep/a/b/hub.md"      # wired through one hop
printf 'vendored\n' >"$REPO/vendor/x/AGENTS.md"     # skipped tree
printf 'module\n' >"$REPO/node_modules/y/AGENTS.md" # skipped tree
commit_all "$REPO"

rc=0
OUT=$(cd "$REPO" && bash "$SCRIPT") || rc=$?
assert_eq "report exits 0 (advisory)" 0 "$rc"
assert_contains "flags the bare nested AGENTS.md" "$OUT" "FAIL [N1]: bare/AGENTS.md"
assert_not_contains "an @AGENTS.md shim wires it" "$OUT" "shimmed/AGENTS.md"
assert_not_contains "a symlinked CLAUDE.md wires it" "$OUT" "linked/AGENTS.md"
assert_not_contains "a gitignored CLAUDE.local.md shim wires it" "$OUT" "localonly/AGENTS.md"
assert_not_contains "a one-hop import chain wires it" "$OUT" "deep/a/b/AGENTS.md"
assert_not_contains "a vendored tree is not examined" "$OUT" "vendor/x/AGENTS.md"
assert_not_contains "node_modules is not examined" "$OUT" "node_modules/y/AGENTS.md"
assert_not_contains "the root AGENTS.md is not examined" "$OUT" "FAIL [N1]: AGENTS.md"

OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "--count == 1" "1" "$OUT"
rc=0
(cd "$REPO" && bash "$SCRIPT" --check) >/dev/null 2>&1 || rc=$?
assert_eq "--check exits 1 with a finding" 1 "$rc"

# --- Case 3: a sibling CLAUDE.md that does not import it is still unwired ---

printf '# Bare\n\nNo import here.\n' >"$REPO/bare/CLAUDE.md"
commit_all "$REPO" "sibling without import"
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "a sibling CLAUDE.md with no import does not wire it" "1" "$OUT"

# --- Case 4: adding the shim clears the finding ---

printf '@AGENTS.md\n' >"$REPO/bare/CLAUDE.md"
commit_all "$REPO" "add shim"
OUT=$(cd "$REPO" && bash "$SCRIPT")
assert_contains "clean repo reports none" "$OUT" "No unwired nested AGENTS.md"
rc=0
(cd "$REPO" && bash "$SCRIPT" --check) >/dev/null 2>&1 || rc=$?
assert_eq "--check exits 0 when clean" 0 "$rc"

# --- Case 5: an untracked nested AGENTS.md is not examined ---

mkdir -p "$REPO/untracked"
printf 'untracked\n' >"$REPO/untracked/AGENTS.md"
OUT=$(cd "$REPO" && bash "$SCRIPT" --count)
assert_eq "untracked files are outside discovery" "0" "$OUT"

# --- Case 6a: a root or ancestor CLAUDE.md that imports the file wires it ---
# The sibling shim is the prescribed layout, but an import from the root
# CLAUDE.md, the root .claude/CLAUDE.md, or an ancestor directory's CLAUDE.md
# brings the file into context too. A file that loads is not a finding.

ENTRY="$TEST_TMPDIR/entry"
make_repo "$ENTRY"
mkdir -p "$ENTRY/.claude" "$ENTRY/byroot" "$ENTRY/bydotclaude" "$ENTRY/anc/mid/leaf" "$ENTRY/still-bare"
printf '# Root\n@byroot/AGENTS.md\n' >"$ENTRY/CLAUDE.md"
# A relative import resolves against the importing file's own directory, so the
# root .claude/CLAUDE.md reaches a sibling-of-root tree through `../`.
printf '@../bydotclaude/AGENTS.md\n' >"$ENTRY/.claude/CLAUDE.md"
printf 'byroot\n' >"$ENTRY/byroot/AGENTS.md"
printf 'bydotclaude\n' >"$ENTRY/bydotclaude/AGENTS.md"
printf '# Ancestor\n@mid/leaf/AGENTS.md\n' >"$ENTRY/anc/CLAUDE.md"
printf 'leaf\n' >"$ENTRY/anc/mid/leaf/AGENTS.md"
printf 'still bare\n' >"$ENTRY/still-bare/AGENTS.md"
commit_all "$ENTRY"

OUT=$(cd "$ENTRY" && bash "$SCRIPT")
assert_not_contains "an import from the root CLAUDE.md wires it" "$OUT" "byroot/AGENTS.md"
assert_not_contains "an import from the root .claude/CLAUDE.md wires it" "$OUT" "bydotclaude/AGENTS.md"
assert_not_contains "an import from an ancestor CLAUDE.md wires it" "$OUT" "anc/mid/leaf/AGENTS.md"
assert_contains "a file no entry point imports is still a finding" "$OUT" "FAIL [N1]: still-bare/AGENTS.md"
OUT=$(cd "$ENTRY" && bash "$SCRIPT" --count)
assert_eq "--count == 1 with three entry-point-wired files" "1" "$OUT"

# --- Case 6b: the four-hop import limit is the loader's, not one more ---
# CLAUDE.md -> h1 -> h2 -> h3 -> AGENTS.md is four hops and loads;
# CLAUDE.md -> h1 -> h2 -> h3 -> h4 -> AGENTS.md is five and does not.

HOPS="$TEST_TMPDIR/hops"
make_repo "$HOPS"
mkdir -p "$HOPS/four" "$HOPS/five"
printf '@h1.md\n' >"$HOPS/four/CLAUDE.md"
printf '@h2.md\n' >"$HOPS/four/h1.md"
printf '@h3.md\n' >"$HOPS/four/h2.md"
printf '@AGENTS.md\n' >"$HOPS/four/h3.md"
printf 'four\n' >"$HOPS/four/AGENTS.md"
printf '@h1.md\n' >"$HOPS/five/CLAUDE.md"
printf '@h2.md\n' >"$HOPS/five/h1.md"
printf '@h3.md\n' >"$HOPS/five/h2.md"
printf '@h4.md\n' >"$HOPS/five/h3.md"
printf '@AGENTS.md\n' >"$HOPS/five/h4.md"
printf 'five\n' >"$HOPS/five/AGENTS.md"
commit_all "$HOPS"

OUT=$(cd "$HOPS" && bash "$SCRIPT")
assert_not_contains "a fourth-hop AGENTS.md is wired" "$OUT" "four/AGENTS.md"
assert_contains "a fifth-hop AGENTS.md is not loaded, so it is a finding" "$OUT" "FAIL [N1]: five/AGENTS.md"

# --- Case 7: no CLAUDE.md above it, so the missing shim is not a finding ---
# Claude Code attaches a subdirectory's AGENTS.md on a Read there when neither
# that directory nor any directory above it carries a CLAUDE.md, .claude/CLAUDE.md
# or CLAUDE.local.md. Nothing blocks it here, so there is nothing to fix.

NATIVE="$TEST_TMPDIR/native"
make_repo "$NATIVE"
mkdir -p "$NATIVE/bare" "$NATIVE/ownclaude"
printf 'root agents\n' >"$NATIVE/AGENTS.md"
printf 'bare\n' >"$NATIVE/bare/AGENTS.md"
printf 'own\n' >"$NATIVE/ownclaude/AGENTS.md"
printf '# Directory notes, no import\n' >"$NATIVE/ownclaude/CLAUDE.md"
commit_all "$NATIVE"

OUT=$(cd "$NATIVE" && bash "$SCRIPT")
assert_not_contains "a bare nested AGENTS.md with no CLAUDE.md above it is not a finding" "$OUT" "bare/AGENTS.md"
assert_contains "a non-importing CLAUDE.md in its own directory still blocks it" "$OUT" "FAIL [N1]: ownclaude/AGENTS.md"
OUT=$(cd "$NATIVE" && bash "$SCRIPT" --count)
assert_eq "--count counts only the blocked one" "1" "$OUT"

printf '@AGENTS.md\n' >"$NATIVE/ownclaude/CLAUDE.md"
commit_all "$NATIVE" "shim the blocked one"
rc=0
(cd "$NATIVE" && bash "$SCRIPT" --check) >/dev/null 2>&1 || rc=$?
assert_eq "--check exits 0 when only unblocked files remain" 0 "$rc"

# --- Case 8: a nested .claude/CLAUDE.md counts, not only the root's ---
# The memory page counts "a CLAUDE.md, .claude/CLAUDE.md, or CLAUDE.local.md in
# your working directory or any directory above it", so a subdirectory's own
# .claude/CLAUDE.md displaces the AGENTS.md beside it exactly as a plain one does.

DOTC="$TEST_TMPDIR/dotclaude"
make_repo "$DOTC"
mkdir -p "$DOTC/blocked/.claude" "$DOTC/wired/.claude" "$DOTC/free"
printf 'root agents\n' >"$DOTC/AGENTS.md"
printf 'blocked\n' >"$DOTC/blocked/AGENTS.md"
printf '# Notes, no import\n' >"$DOTC/blocked/.claude/CLAUDE.md"
printf 'wired\n' >"$DOTC/wired/AGENTS.md"
printf '@../AGENTS.md\n' >"$DOTC/wired/.claude/CLAUDE.md"
printf 'free\n' >"$DOTC/free/AGENTS.md"
commit_all "$DOTC"

OUT=$(cd "$DOTC" && bash "$SCRIPT")
assert_contains "a nested .claude/CLAUDE.md with no import is a finding" "$OUT" "FAIL [N1]: blocked/AGENTS.md"
assert_not_contains "a nested .claude/CLAUDE.md that imports it wires it" "$OUT" "wired/AGENTS.md"
assert_not_contains "a directory with none of the three is not a finding" "$OUT" "free/AGENTS.md"

# --- Case 9: another tool's directory hides its AGENTS.md, not a CLAUDE.md ---
# The exclusion is about whose file it is, and only an AGENTS.md under
# .codex/.cursor/.github belongs to that tool. A CLAUDE.md there is Claude's.

OWNED="$TEST_TMPDIR/owned"
make_repo "$OWNED"
mkdir -p "$OWNED/.cursor" "$OWNED/.github"
printf '@AGENTS.md\n' >"$OWNED/CLAUDE.md"
printf 'root agents\n' >"$OWNED/AGENTS.md"
printf 'cursor\n' >"$OWNED/.cursor/AGENTS.md"
printf '# Cursor-dir notes for Claude, no import\n' >"$OWNED/.cursor/CLAUDE.md"
printf '# Workflow notes for Claude\n' >"$OWNED/.github/CLAUDE.md"
commit_all "$OWNED"

OUT=$(cd "$OWNED" && bash "$SCRIPT")
assert_not_contains "another tool's AGENTS.md is never a finding" "$OUT" ".cursor/AGENTS.md"
OUT=$(cd "$OWNED" && bash "$SCRIPT" --count)
assert_eq "and a Claude CLAUDE.md there is not an AGENTS.md finding either" "0" "$OUT"

# --- Case 6: a repo with no nested AGENTS.md at all ---

NONE="$TEST_TMPDIR/none"
make_repo "$NONE"
printf '# Root\n' >"$NONE/CLAUDE.md"
commit_all "$NONE"
OUT=$(cd "$NONE" && bash "$SCRIPT" --count)
assert_eq "no nested AGENTS.md => 0" "0" "$OUT"

report_and_exit
