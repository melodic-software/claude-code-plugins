#!/usr/bin/env bash
# Regression tests for detect.sh — the audit's deterministic fact emitter.
#
# The line ranges this script emits are what `realign` excises by, so the
# SECTION assertions below check exact numbers rather than presence: an
# off-by-one here removes the wrong text from someone's instruction file.
#
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
#
# shellcheck disable=SC2016 # fixtures contain literal markdown fences, globs,
# and @import tokens; backticks and $ are file content, never expansions.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/detect.sh"

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
assert_has() {
  if [[ $'\n'"$2"$'\n' == *$'\n'"$3"$'\n'* ]]; then pass "$1"; else fail "$1" "row: $3" "$2"; fi
}
assert_lacks_sub() {
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "must not contain: $3" "$2"; fi
}

run() { bash "$SCRIPT" "$@" 2>&1; }

commit_all() {
  git -C "$1" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
}

# ==========================================================================
# Usage
# ==========================================================================
out="$(run --help)"
assert_has "--help prints usage" "$(printf '%s' "$out" | head -1)" "detect.sh — deterministic fact emitter for instruction-placement's audit."

run --tier bogus >/dev/null 2>&1
assert_eq "an unknown --tier is a usage error" "2" "$?"
run --root /nonexistent-xyz >/dev/null 2>&1
assert_eq "an unusable --root is a usage error" "2" "$?"

# ==========================================================================
# Section segmentation — exact line ranges
# ==========================================================================
repo="$(mktemp -d)"
git -C "$repo" init -q .
cat >"$repo/CLAUDE.md" <<'EOF'
# Project

Intro line.

## Build

Run make build.

## C# naming

Interfaces must be prefixed with I.
Async methods must end in Async.

### Nested detail

More text.
EOF
commit_all "$repo"

out="$(run --root "$repo" -- CLAUDE.md)"
assert_has "FILE record carries tier and line count" "$out" "$(printf 'FILE\tCLAUDE.md\tcore\t16')"
assert_has "first section spans to the line before the next heading" "$out" "$(printf 'SECTION\tCLAUDE.md\t1\t4\t1\tProject')"
assert_has "a level-2 section is recorded with its level" "$out" "$(printf 'SECTION\tCLAUDE.md\t5\t8\t2\tBuild')"
assert_has "a section ends where the next heading begins" "$out" "$(printf 'SECTION\tCLAUDE.md\t9\t13\t2\tC# naming')"
assert_has "the final section runs to end of file" "$out" "$(printf 'SECTION\tCLAUDE.md\t14\t16\t3\tNested detail')"

# ==========================================================================
# Normative signal
# ==========================================================================
assert_has "normative markers are counted and named" "$out" "$(printf 'SIGNAL\tCLAUDE.md\t9\t2\tmust')"
assert_lacks_sub "a section with no normative language emits no SIGNAL" \
  "$(printf '%s\n' "$out" | grep '^SIGNAL' | grep "$(printf '\t5\t')" || true)" "SIGNAL"

sig="$(mktemp -d)"
git -C "$sig" init -q .
cat >"$sig/AGENTS.md" <<'EOF'
# Rules

You must do this. Never do that. Do not do the other.
Always prefer X over Y.
EOF
commit_all "$sig"
out_sig="$(run --root "$sig" -- AGENTS.md)"
markers="$(printf '%s\n' "$out_sig" | awk -F'\t' '$1=="SIGNAL"{print $5}')"
assert_eq "markers are emitted in deterministic sorted order" "always,do-not,must,never,prefer" "$markers"

# ==========================================================================
# Frontmatter and fenced blocks are excluded
# ==========================================================================
fence="$(mktemp -d)"
git -C "$fence" init -q .
cat >"$fence/AGENTS.md" <<'EOF'
---
description: "must never always"
---

# Real

Prose here.

```markdown
You must never do this inside an example.
Files named *.fake should be ignored.
```

Closing prose.
EOF
commit_all "$fence"
out_f="$(run --root "$fence" -- AGENTS.md)"
assert_lacks_sub "frontmatter words do not count as normative signal" "$out_f" "$(printf 'SIGNAL\tAGENTS.md\t')"
assert_lacks_sub "an extension inside a fence is not a hint" "$out_f" ".fake"

# ==========================================================================
# Glob-derivation hints
# ==========================================================================
hint="$(mktemp -d)"
git -C "$hint" init -q .
cat >"$hint/AGENTS.md" <<'EOF'
# Conventions

All `*.cs` files follow the naming rules.
Test files use the `*.test.ts` suffix.
Handlers live under `src/api/`.
We write C# for the backend and Python for tooling.
See corpus.md for details, e.g. the exclusions.
EOF
commit_all "$hint"
out_h="$(run --root "$hint" -- AGENTS.md)"
assert_has "a literal extension becomes an ext hint" "$out_h" "$(printf 'HINT\tAGENTS.md\t1\text\t.cs')"
assert_has "a dotted run emits its full form" "$out_h" "$(printf 'HINT\tAGENTS.md\t1\text\t.test.ts')"
assert_has "a dotted run also emits its final segment" "$out_h" "$(printf 'HINT\tAGENTS.md\t1\text\t.ts')"
assert_has "a quoted directory becomes a dir hint" "$out_h" "$(printf 'HINT\tAGENTS.md\t1\tdir\tsrc/api/')"
assert_has "a named language maps to its extension" "$out_h" "$(printf 'HINT\tAGENTS.md\t1\tlang\t.cs')"
assert_has "a second named language also maps" "$out_h" "$(printf 'HINT\tAGENTS.md\t1\tlang\t.py')"
assert_lacks_sub "a dot inside a word is not an extension" "$out_h" "$(printf 'ext\t.md')"
assert_lacks_sub "an abbreviation like e.g. is not an extension" "$out_h" "$(printf 'ext\t.g')"

# ==========================================================================
# Rule inventory
# ==========================================================================
rules="$(mktemp -d)"
git -C "$rules" init -q .
mkdir -p "$rules/.claude/rules" "$rules/pkg/.claude/rules" "$rules/ext"
printf 'class X {}\n' >"$rules/a.cs"
printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# Scoped\n' >"$rules/.claude/rules/scoped.md"
printf '# Unscoped rule\n\nAlways loaded.\n' >"$rules/.claude/rules/plain.md"
printf -- '---\npaths: ["pkg/**"]\n---\n\n# Nested\n' >"$rules/pkg/.claude/rules/nested.md"
printf -- '---\npaths: ["**/*.cs"]\n---\n\n# Linked\n' >"$rules/ext/linked.md"
ln -s "$rules/ext/linked.md" "$rules/.claude/rules/linked.md"
commit_all "$rules"

out_r="$(run --root "$rules")"
assert_has "a scoped rule is inventoried with its globs" "$out_r" "$(printf 'RULE\t.claude/rules/scoped.md\tscoped\t**/*.cs')"
assert_has "an unscoped rule is inventoried as unscoped" "$out_r" "$(printf 'RULE\t.claude/rules/plain.md\tunscoped\t-')"
assert_has "a nested rules tree is inventoried" "$out_r" "$(printf 'RULE\tpkg/.claude/rules/nested.md\tscoped\tpkg/**')"
assert_has "a symlinked rule is inventoried" "$out_r" "$(printf 'RULE\t.claude/rules/linked.md\tscoped\t**/*.cs')"

# ==========================================================================
# Corpus exclusions and tiering
# ==========================================================================
corp="$(mktemp -d)"
git -C "$corp" init -q .
mkdir -p "$corp/docs" "$corp/vendor/x" "$corp/node_modules/y" "$corp/skills/s/evals/fixtures"
printf '# Root\n' >"$corp/CLAUDE.md"
printf '# Changes\n' >"$corp/CHANGELOG.md"
printf '# Guide\n' >"$corp/docs/guide.md"
printf '# Contributing\n' >"$corp/CONTRIBUTING.md"
printf '# Vendored\n' >"$corp/vendor/x/AGENTS.md"
printf '# Dep\n' >"$corp/node_modules/y/CLAUDE.md"
printf '# Fixture\n' >"$corp/skills/s/evals/fixtures/bad.md"
commit_all "$corp"

out_c="$(run --root "$corp")"
assert_has "CHANGELOG.md is skipped by corpus rules" "$out_c" "$(printf 'SKIP\tCHANGELOG.md\texcluded by corpus rules')"
assert_has "an evals fixture is skipped" "$out_c" "$(printf 'SKIP\tskills/s/evals/fixtures/bad.md\texcluded by corpus rules')"
assert_has "a vendored tree is skipped" "$out_c" "$(printf 'SKIP\tvendor/x/AGENTS.md\texcluded by corpus rules')"
assert_has "node_modules is skipped" "$out_c" "$(printf 'SKIP\tnode_modules/y/CLAUDE.md\texcluded by corpus rules')"
assert_has "a named contributor surface is tiered" "$out_c" "$(printf 'FILE\tCONTRIBUTING.md\tnamed\t1')"
assert_has "a docs tree file is tiered" "$out_c" "$(printf 'FILE\tdocs/guide.md\tdocs\t1')"

# An excluded path that ALSO lives in a `.claude/rules` tree reaches the file
# list by two routes: the tracked walk (which skips it) and the symlink backfill
# from ip_discover_rules (which used to re-add it, because it only asked "is this
# already in FILES"). The result was a SKIP row and a FILE row for one path, and
# a double count in the summary. `context/corpus.md` says exclusions are absolute
# and applied before any classification, so this pins BOTH halves: skipped, and
# not silently re-admitted.
excl="$(mktemp -d)"
git -C "$excl" init -q .
mkdir -p "$excl/vendor/pkg/.claude/rules"
printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# Vendored rule\n' \
  >"$excl/vendor/pkg/.claude/rules/v.md"
printf '# Root\n' >"$excl/CLAUDE.md"
commit_all "$excl"

out_x="$(run --root "$excl")"
assert_has "a rule inside an excluded tree is skipped" "$out_x" \
  "$(printf 'SKIP\tvendor/pkg/.claude/rules/v.md\texcluded by corpus rules')"
if [[ "$out_x" == *"$(printf 'FILE\tvendor/pkg/.claude/rules/v.md')"* ]]; then
  fail "and the backfill does not re-admit it" "no FILE row for the excluded rule" "$out_x"
else
  pass "and the backfill does not re-admit it"
fi
rm -rf "$excl"

out_core="$(run --root "$corp" --tier core)"
assert_has "core tier keeps the instruction layer" "$out_core" "$(printf 'FILE\tCLAUDE.md\tcore\t1')"
assert_has "core tier skips ordinary documentation" "$out_core" "$(printf 'SKIP\tdocs/guide.md\toutside the core tier')"
assert_lacks_sub "core tier emits no FILE row for docs" "$out_core" "$(printf 'FILE\tdocs/guide.md')"

# ==========================================================================
# Determinism, and no silent awk failure
# ==========================================================================
a="$(run --root "$rules")"
b="$(run --root "$rules")"
assert_eq "output is byte-identical across runs" "$a" "$b"

# A regex the awk engine cannot compile used to print a panic to stderr and an
# empty fact set to stdout, which reads exactly like "this file has no sections".
assert_lacks_sub "no awk panic reaches the output" "$out" "panic"
assert_lacks_sub "no awk syntax error reaches the output" "$out" "syntax error"
sections="$(printf '%s\n' "$out" | grep -c '^SECTION' || true)"
assert_eq "a headed file yields a non-zero section count" "4" "$sections"

# ==========================================================================
rm -rf "$repo" "$sig" "$fence" "$hint" "$rules" "$corp"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
