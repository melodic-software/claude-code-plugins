#!/usr/bin/env bash
# Regression tests for lib/discover.sh — the shared discovery layer.
#
# WHY THIS FILE EXISTS. Version 0.1.0 shipped 92 tests covering glob SEMANTICS
# exhaustively and file DISCOVERY barely. All four bugs found by probing after
# release were in the discovery layer, so it gets its own suite and its own
# fixtures rather than being tested incidentally through the engines.
#
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
#
# shellcheck disable=SC2016 # fixtures contain literal markdown code fences and
# @import tokens; the backticks are file content, never command substitution.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./discover.sh
. "$SCRIPT_DIR/discover.sh"

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
assert_lists() {
  # $1 label, $2 newline-separated expected, $3 actual
  local want actual
  want="$(printf '%s\n' "$2" | grep -c . || true)"
  actual="$(printf '%s\n' "$3" | grep -c . || true)"
  if [[ "$2" == "$3" ]]; then
    pass "$1"
  else
    fail "$1" "$2 ($want entries)" "$3 ($actual entries)"
  fi
}
assert_has() {
  if [[ $'\n'"$2"$'\n' == *$'\n'"$3"$'\n'* ]]; then
    pass "$1"
  else
    fail "$1" "list contains: $3" "$2"
  fi
}
assert_lacks() {
  if [[ $'\n'"$2"$'\n' != *$'\n'"$3"$'\n'* ]]; then
    pass "$1"
  else
    fail "$1" "list must NOT contain: $3" "$2"
  fi
}

commit_all() {
  git -C "$1" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
}

rule_file() {
  mkdir -p "$(dirname "$1")"
  {
    printf -- '---\npaths:\n  - "%s"\n---\n\n# %s\n' "$2" "$3"
  } >"$1"
}

# ==========================================================================
# BUG (a) — rules in a NESTED .claude/rules tree
# ==========================================================================
repo="$(mktemp -d)"
git -C "$repo" init -q .
rule_file "$repo/.claude/rules/root.md" '**/*.cs' 'Root rule'
rule_file "$repo/packages/web/.claude/rules/web.md" 'packages/web/**/*.ts' 'Web rule'
rule_file "$repo/packages/api/.claude/rules/deep/api.md" 'packages/api/**' 'API rule'
commit_all "$repo"

out="$(ip_discover_rules "$repo")"
assert_has "a root rules tree is discovered" "$out" ".claude/rules/root.md"
assert_has "a nested package rules tree is discovered" "$out" "packages/web/.claude/rules/web.md"
assert_has "a subdirectory inside a nested rules tree is discovered" "$out" "packages/api/.claude/rules/deep/api.md"

# ==========================================================================
# BUG (b) — symlinked rule FILE and symlinked rule DIRECTORY
# Documented upstream: ".claude/rules/ supports symlinks, so you can maintain
# a shared set of rules and link them into multiple projects."
# ==========================================================================
sym="$(mktemp -d)"
git -C "$sym" init -q .
rule_file "$sym/.claude/rules/local.md" '**/*.cs' 'Local rule'
rule_file "$sym/external/security.md" '**/*.cs' 'Shared security rule'
mkdir -p "$sym/external-dir"
rule_file "$sym/external-dir/style.md" '**/*.cs' 'Shared style rule'
ln -s "$sym/external/security.md" "$sym/.claude/rules/security.md"
ln -s "$sym/external-dir" "$sym/.claude/rules/shared"
commit_all "$sym"

out="$(ip_discover_rules "$sym")"
assert_has "a plain rule file is discovered alongside symlinks" "$out" ".claude/rules/local.md"
assert_has "a SYMLINKED rule file is discovered" "$out" ".claude/rules/security.md"
assert_has "a rule inside a SYMLINKED directory is discovered" "$out" ".claude/rules/shared/style.md"

# The rules ROOT itself being a symlink is the documented way to share one whole
# rule set across projects. The first symlink fix followed links INSIDE the tree
# and missed the tree root, which loses every shared rule rather than one.
symroot="$(mktemp -d)"
git -C "$symroot" init -q .
mkdir -p "$symroot/.claude" "$symroot/shared"
rule_file "$symroot/shared/security.md" '**/*.cs' 'Shared security rule'
rule_file "$symroot/shared/style.md" '**/*.cs' 'Shared style rule'
ln -s "$symroot/shared" "$symroot/.claude/rules"
commit_all "$symroot"

out="$(ip_discover_rules "$symroot")"
assert_has "a SYMLINKED rules root is traversed" "$out" ".claude/rules/security.md"
assert_has "every rule under a symlinked root is found" "$out" ".claude/rules/style.md"

# A `.claude` directory that is itself a symlink is the same shape one level up.
symclaude="$(mktemp -d)"
git -C "$symclaude" init -q .
mkdir -p "$symclaude/external/rules"
rule_file "$symclaude/external/rules/x.md" '**/*.cs' 'External rule'
ln -s "$symclaude/external" "$symclaude/.claude"
commit_all "$symclaude"
out="$(ip_discover_rules "$symclaude")"
assert_has "a symlinked .claude directory is traversed" "$out" ".claude/rules/x.md"

# --------------------------------------------------------------------------
# `paths:` parsing — one parser, and brace commas are not list separators
# --------------------------------------------------------------------------
pp="$(mktemp -d)"
rule_file "$pp/block.md" 'src/**/*.ts' 'Block'
cat >"$pp/flow-brace.md" <<'EOF'
---
paths: ["src/*.{ts,tsx}"]
---

# Flow with a brace group
EOF
cat >"$pp/flow-multi.md" <<'EOF'
---
paths: ["src/*.{ts,tsx}", 'lib/**/*.js', bare/**/*.md]
---

# Flow with several entries
EOF
cat >"$pp/flow-bracket.md" <<'EOF'
---
paths: ["photos/a[0-9].png"]
---

# Flow carrying a bracket expression
EOF

out="$(ip_parse_paths "$pp/flow-brace.md")"
assert_lists "a brace comma is not a list separator" 'src/*.{ts,tsx}' "$out"

out="$(ip_parse_paths "$pp/flow-multi.md")"
assert_has "the braced entry survives alongside others" "$out" 'src/*.{ts,tsx}'
assert_has "a single-quoted entry is unquoted" "$out" 'lib/**/*.js'
assert_has "an unquoted entry is kept" "$out" 'bare/**/*.md'
assert_eq "the flow list yields exactly three entries" "3" "$(printf '%s\n' "$out" | grep -c .)"

out="$(ip_parse_paths "$pp/flow-bracket.md")"
assert_lists "a bracket expression inside a flow entry survives" 'photos/a[0-9].png' "$out"

out="$(ip_parse_paths "$pp/block.md")"
assert_lists "the block-sequence form still parses" 'src/**/*.ts' "$out"

# A circular symlink must not hang or explode the listing.
circ="$(mktemp -d)"
git -C "$circ" init -q .
mkdir -p "$circ/.claude/rules"
rule_file "$circ/.claude/rules/ok.md" '**/*.cs' 'Fine'
ln -s "$circ/.claude/rules" "$circ/.claude/rules/loop"
commit_all "$circ"
out="$(timeout 20 bash -c ". '$SCRIPT_DIR/discover.sh'; ip_discover_rules '$circ'" 2>/dev/null)"
rc=$?
assert_eq "a circular symlink does not hang discovery" "0" "$rc"
assert_has "a circular symlink still yields the real rule" "$out" ".claude/rules/ok.md"
dupes="$(printf '%s\n' "$out" | sort | uniq -d | grep -c . || true)"
assert_eq "discovery emits no duplicate paths under a symlink loop" "0" "$dupes"

# ==========================================================================
# BUG (c) — untracked and gitignored nested instruction files
# corpus.md: untracked files are not swept; vendor trees are never swept.
# ==========================================================================
track="$(mktemp -d)"
git -C "$track" init -q .
mkdir -p "$track/pkg" "$track/vendor/thirdparty" "$track/node_modules/dep" "$track/svc"
printf 'vendor/\nnode_modules/\n' >"$track/.gitignore"
printf '# Tracked service conventions\n' >"$track/svc/AGENTS.md"
printf 'x\n' >"$track/svc/a.txt"
commit_all "$track"
# Created AFTER the commit, so they are genuinely untracked.
printf '# Untracked scratch conventions\n' >"$track/pkg/AGENTS.md"
printf '# Vendored third-party conventions\n' >"$track/vendor/thirdparty/AGENTS.md"
printf '# Dependency conventions\n' >"$track/node_modules/dep/CLAUDE.md"

out="$(ip_discover_nested_instructions "$track")"
assert_has "a tracked nested instruction file is discovered" "$out" "svc/AGENTS.md"
assert_lacks "an UNTRACKED nested instruction file is excluded" "$out" "pkg/AGENTS.md"
assert_lacks "a GITIGNORED vendor tree is excluded" "$out" "vendor/thirdparty/AGENTS.md"
assert_lacks "node_modules is excluded" "$out" "node_modules/dep/CLAUDE.md"

# Root-level instruction files already load at session start — never "nested".
root_files="$(mktemp -d)"
git -C "$root_files" init -q .
printf '@AGENTS.md\n' >"$root_files/CLAUDE.md"
printf '# Root\n' >"$root_files/AGENTS.md"
mkdir -p "$root_files/sub"
printf '# Sub\n' >"$root_files/sub/AGENTS.md"
commit_all "$root_files"
out="$(ip_discover_nested_instructions "$root_files")"
assert_lacks "the root CLAUDE.md is not a nested surface" "$out" "CLAUDE.md"
assert_lacks "the root AGENTS.md is not a nested surface" "$out" "AGENTS.md"
assert_has "a subdirectory instruction file is a nested surface" "$out" "sub/AGENTS.md"

# ==========================================================================
# BUG (d) — index target must actually be reachable by Claude Code
# ==========================================================================
chain="$(mktemp -d)"
git -C "$chain" init -q .
printf '# Claude instructions\n\nNothing imported here.\n' >"$chain/CLAUDE.md"
printf '# Shared agent instructions\n' >"$chain/AGENTS.md"
commit_all "$chain"

ip_index_target_loaded "$chain" "AGENTS.md" >/dev/null 2>&1
assert_eq "an AGENTS.md nothing imports is reported unreachable" "1" "$?"
reason="$(ip_index_target_loaded "$chain" "AGENTS.md" 2>&1)"
assert_eq "the unreachable verdict names the missing import" "UNREACHABLE" "$(printf '%s' "$reason" | cut -f1)"

printf '@AGENTS.md\n\n# Claude instructions\n' >"$chain/CLAUDE.md"
commit_all "$chain"
ip_index_target_loaded "$chain" "AGENTS.md" >/dev/null 2>&1
assert_eq "an imported AGENTS.md is reachable" "0" "$?"

# A CLAUDE.md target is always reachable — it is a root memory file itself.
ip_index_target_loaded "$chain" "CLAUDE.md" >/dev/null 2>&1
assert_eq "a root CLAUDE.md target is reachable" "0" "$?"

# The documented symlink alternative to the import.
symlinked="$(mktemp -d)"
git -C "$symlinked" init -q .
printf '# Shared agent instructions\n' >"$symlinked/AGENTS.md"
ln -s AGENTS.md "$symlinked/CLAUDE.md"
commit_all "$symlinked"
ip_index_target_loaded "$symlinked" "AGENTS.md" >/dev/null 2>&1
assert_eq "a CLAUDE.md symlinked to AGENTS.md makes it reachable" "0" "$?"

# An import inside a fenced code block is not a real import.
fenced="$(mktemp -d)"
git -C "$fenced" init -q .
{
  printf '# Claude instructions\n\n'
  printf 'To wire this up, add:\n\n'
  printf '```markdown\n@AGENTS.md\n```\n'
} >"$fenced/CLAUDE.md"
printf '# Shared\n' >"$fenced/AGENTS.md"
commit_all "$fenced"
ip_index_target_loaded "$fenced" "AGENTS.md" >/dev/null 2>&1
assert_eq "an @import inside a code fence does not count as an import" "1" "$?"

# The `.claude/CLAUDE.md` project location is equally valid.
alt="$(mktemp -d)"
git -C "$alt" init -q .
mkdir -p "$alt/.claude"
printf '@../AGENTS.md\n' >"$alt/.claude/CLAUDE.md"
printf '# Shared\n' >"$alt/AGENTS.md"
commit_all "$alt"
ip_index_target_loaded "$alt" "AGENTS.md" >/dev/null 2>&1
assert_eq "an import from .claude/CLAUDE.md also makes the target reachable" "0" "$?"

# ==========================================================================
# Determinism
# ==========================================================================
a="$(ip_discover_rules "$repo")"
b="$(ip_discover_rules "$repo")"
assert_lists "rules discovery is byte-identical across runs" "$a" "$b"

# ==========================================================================
rm -rf "$repo" "$sym" "$symroot" "$symclaude" "$pp" "$circ" "$track" "$root_files" "$chain" "$symlinked" "$fenced" "$alt"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
