#!/usr/bin/env bash
# Regression tests for glob-tools.sh (self-contained — no external test lib).
#
# Every case runs against a deterministic throwaway git fixture under mktemp, so
# the tracked-file universe is known exactly and match counts are assertable.
#
# fixture-isolation-scope: this suite builds git fixtures and clears the
# inherited git environment itself rather than sourcing a harness, so the plugin
# stays self-contained and portable outside this marketplace.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/glob-tools.sh"

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

# Build a fixture repo with a known tracked-file set.
#   fixture_repo <relative-path> [<relative-path>...]
fixture_repo() {
  local dir
  dir="$(mktemp -d)"
  local rel
  for rel in "$@"; do
    mkdir -p "$dir/$(dirname "$rel")"
    printf 'x\n' >"$dir/$rel"
  done
  git -C "$dir" init -q .
  git -C "$dir" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
  git -C "$dir" -c user.email=t@t -c user.name=t commit -qm t >/dev/null 2>&1
  printf '%s' "$dir"
}

run() { bash "$SCRIPT" "$@" 2>&1; }

# Pull one PATTERN row's field N (1-indexed within the tab-split row).
row_field() {
  printf '%s\n' "$1" | awk -F'\t' -v pat="$2" -v f="$3" '$1=="PATTERN" && $3==pat {print $f}'
}

# --------------------------------------------------------------------------
# Usage and argument handling
# --------------------------------------------------------------------------
out="$(run --help)"
assert_contains "--help prints usage" "$out" "glob-tools.sh"

run >/dev/null 2>&1
assert_eq "no arguments is a usage error" "2" "$?"

run bogus --glob 'x' >/dev/null 2>&1
assert_eq "unknown subcommand is a usage error" "2" "$?"

run validate >/dev/null 2>&1
assert_eq "validate with no --glob is a usage error" "2" "$?"

run validate --glob 'x' --root /nonexistent-path-xyz >/dev/null 2>&1
assert_eq "unusable --root is a usage error" "2" "$?"

run validate --glob 'x' --breadth-max abc >/dev/null 2>&1
assert_eq "non-integer --breadth-max is a usage error" "2" "$?"

# --------------------------------------------------------------------------
# Core matching semantics
# --------------------------------------------------------------------------
repo="$(fixture_repo "a.ts" "src/b.ts" "src/deep/c.ts" "src/notes.md" "README.md")"

out="$(run validate --root "$repo" --glob '**/*.ts')"
assert_eq "**/*.ts matches root and nested TypeScript" "3" "$(row_field "$out" '**/*.ts' 5)"

out="$(run validate --root "$repo" --glob '*.md')"
assert_eq "*.md is root-only, does not cross a separator" "1" "$(row_field "$out" '*.md' 5)"

out="$(run validate --root "$repo" --glob 'src/**/*')"
assert_eq "src/**/* matches everything under src" "3" "$(row_field "$out" 'src/**/*' 5)"

out="$(run validate --root "$repo" --glob 'src/*.ts')"
assert_eq "src/*.ts does not descend into src/deep" "1" "$(row_field "$out" 'src/*.ts' 5)"

out="$(run validate --root "$repo" --glob 'src/deep/c.ts')"
assert_eq "a literal path matches exactly one file" "1" "$(row_field "$out" 'src/deep/c.ts' 5)"

# A dot in a pattern is a literal dot, not a regex wildcard.
repo_dot="$(fixture_repo "axts" "a.ts")"
out="$(run validate --root "$repo_dot" --glob '*.ts')"
assert_eq "a dot in a glob is literal, not a regex wildcard" "1" "$(row_field "$out" '*.ts' 5)"

# --------------------------------------------------------------------------
# Brace expansion
# --------------------------------------------------------------------------
repo_brace="$(fixture_repo "src/a.ts" "src/b.tsx" "src/c.js")"

out="$(run validate --root "$repo_brace" --glob 'src/*.{ts,tsx}')"
assert_eq "brace group expands to two patterns" "2" "$(row_field "$out" 'src/*.{ts,tsx}' 4)"
assert_eq "brace group unions its matches" "2" "$(row_field "$out" 'src/*.{ts,tsx}' 5)"

repo_nested="$(fixture_repo "a/c/x.ts" "a/d/x.ts" "b/c/x.ts" "b/d/x.ts" "z/z/x.ts")"
out="$(run validate --root "$repo_nested" --glob '{a,b}/{c,d}/*.ts')"
assert_eq "nested brace groups multiply to four patterns" "4" "$(row_field "$out" '{a,b}/{c,d}/*.ts' 4)"
assert_eq "nested brace groups match only their cartesian product" "4" "$(row_field "$out" '{a,b}/{c,d}/*.ts' 5)"

# 2^10 = 1024 expansions, past the documented 1,000-pattern budget.
bomb='{a,b}/{c,d}/{e,f}/{g,h}/{i,j}/{k,l}/{m,n}/{o,p}/{q,r}/{s,t}/*.ts'
out="$(run validate --root "$repo" --glob "$bomb")"
assert_eq "a pattern past the brace budget is over-budget" "over-budget" "$(row_field "$out" "$bomb" 6)"
run validate --root "$repo" --glob "$bomb" >/dev/null 2>&1
assert_eq "over-budget exits 1" "1" "$?"

# A brace-free pattern must never be charged against the budget.
out="$(run validate --root "$repo" --glob '**/*.ts')"
assert_eq "a brace-free pattern expands to exactly one" "1" "$(row_field "$out" '**/*.ts' 4)"

# --------------------------------------------------------------------------
# Bracket expressions
# --------------------------------------------------------------------------
repo_br="$(fixture_repo "a1.ts" "a2.ts" "a9.ts" "photos [2024/x.png")"

out="$(run validate --root "$repo_br" --glob 'a[12].ts')"
assert_eq "a valid bracket expression matches its set" "2" "$(row_field "$out" 'a[12].ts' 5)"

out="$(run validate --root "$repo_br" --glob 'a[!12].ts')"
assert_eq "a negated bracket expression excludes its set" "1" "$(row_field "$out" 'a[!12].ts' 5)"

out="$(run validate --root "$repo_br" --glob 'photos [2024/**')"
assert_eq "an unclosed bracket expression is bad-bracket" "bad-bracket" "$(row_field "$out" 'photos [2024/**' 6)"
run validate --root "$repo_br" --glob 'photos [2024/**' >/dev/null 2>&1
assert_eq "bad-bracket exits 1" "1" "$?"

out="$(run validate --root "$repo_br" --glob 'photos \[2024/**')"
assert_eq "an escaped bracket is treated as a literal" "1" "$(row_field "$out" 'photos \[2024/**' 5)"

# An escaped `]` inside a bracket expression must not end it early. The validity
# check and the regex builder have to agree on where the expression closes, or a
# pattern that validates produces a regex matching the wrong set.
repo_esc="$(fixture_repo "a1.ts" "ax.ts")"
out="$(run validate --root "$repo_esc" --glob 'a[1\]].ts')"
esc_status="$(row_field "$out" 'a[1\]].ts' 6)"
if [[ "$esc_status" == "bad-bracket" ]]; then
  fail "an escaped ] inside a bracket expression does not close it" "not bad-bracket" "$esc_status"
else
  pass "an escaped ] inside a bracket expression does not close it"
fi

# --------------------------------------------------------------------------
# Zero-match and breadth
# --------------------------------------------------------------------------
out="$(run validate --root "$repo" --glob 'nowhere/**/*.rs')"
assert_eq "a glob matching nothing is zero-match" "zero-match" "$(row_field "$out" 'nowhere/**/*.rs' 6)"
run validate --root "$repo" --glob 'nowhere/**/*.rs' >/dev/null 2>&1
assert_eq "zero-match exits 1" "1" "$?"

out="$(run validate --root "$repo" --glob '**/*')"
assert_eq "a glob matching the whole repo is over-broad" "over-broad" "$(row_field "$out" '**/*' 6)"
run validate --root "$repo" --glob '**/*' >/dev/null 2>&1
assert_eq "over-broad is a warning, not a failure — exits 0" "0" "$?"

# Breadth is configurable, and the threshold is what moves the verdict.
out="$(run validate --root "$repo" --glob '**/*.ts' --breadth-max 10)"
assert_eq "a low breadth ceiling reclassifies a narrow glob" "over-broad" "$(row_field "$out" '**/*.ts' 6)"
out="$(run validate --root "$repo" --glob '**/*.ts' --breadth-max 99)"
assert_eq "a high breadth ceiling leaves it ok" "ok" "$(row_field "$out" '**/*.ts' 6)"

# --------------------------------------------------------------------------
# Untracked files are outside the match universe
# --------------------------------------------------------------------------
printf 'x\n' >"$repo/untracked.ts"
out="$(run validate --root "$repo" --glob '**/*.ts')"
assert_eq "untracked files do not count as matches" "3" "$(row_field "$out" '**/*.ts' 5)"
rm -f "$repo/untracked.ts"

# --------------------------------------------------------------------------
# The rules subcommand — frontmatter extraction
# --------------------------------------------------------------------------
rules_repo="$(fixture_repo "src/a.ts" "src/b.tsx" "docs/x.md")"
mkdir -p "$rules_repo/.claude/rules/nested"

cat >"$rules_repo/.claude/rules/block.md" <<'EOF'
---
paths:
  - "src/**/*.ts"
  - 'src/**/*.tsx'
---

Block sequence form.
EOF

cat >"$rules_repo/.claude/rules/inline.md" <<'EOF'
---
paths: ["docs/**/*.md"]
---

Inline flow-sequence form.
EOF

cat >"$rules_repo/.claude/rules/unscoped.md" <<'EOF'
No frontmatter at all — an unscoped rule contributes no patterns.
EOF

cat >"$rules_repo/.claude/rules/nested/broken.md" <<'EOF'
---
paths:
  - "nowhere/**/*.rs"
---

Recursively discovered, and its glob matches nothing.
EOF

git -C "$rules_repo" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$rules_repo" -c user.email=t@t -c user.name=t commit -qm rules >/dev/null 2>&1

out="$(run rules --root "$rules_repo")"
# `*.ts` must not match `b.tsx` — the extension boundary is anchored.
assert_eq "block-sequence paths are extracted" "1" "$(row_field "$out" 'src/**/*.ts' 5)"
assert_eq "quoted single-quote entries are extracted" "1" "$(row_field "$out" 'src/**/*.tsx' 5)"
assert_eq "inline flow-sequence paths are extracted" "1" "$(row_field "$out" 'docs/**/*.md' 5)"
assert_contains "nested rule directories are discovered" "$out" "nested/broken.md"
assert_eq "a nested rule's broken glob is reported" "zero-match" "$(row_field "$out" 'nowhere/**/*.rs' 6)"
assert_contains "an unscoped rule contributes no pattern row" \
  "$(printf '%s\n' "$out" | awk -F'\t' '$1=="PATTERN"{print $2}' | sort -u | tr '\n' ' ')" \
  ".claude/rules/block.md"

if printf '%s\n' "$out" | grep -q 'unscoped.md'; then
  fail "an unscoped rule contributes no pattern row" "no unscoped.md row" "$out"
else
  pass "an unscoped rule contributes no pattern row"
fi

run rules --root "$rules_repo" >/dev/null 2>&1
assert_eq "rules exits 1 when any rule glob is invalid" "1" "$?"

# A repo with no rules directory is a clean pass, not an error.
clean_repo="$(fixture_repo "a.ts")"
out="$(run rules --root "$clean_repo")"
assert_contains "a repo with no rules tree summarizes zero patterns" "$out" "SUMMARY"
run rules --root "$clean_repo" >/dev/null 2>&1
assert_eq "a repo with no rules tree exits 0" "0" "$?"

# --------------------------------------------------------------------------
# Determinism and safety
# --------------------------------------------------------------------------
a="$(run rules --root "$rules_repo")"
b="$(run rules --root "$rules_repo")"
assert_eq "output is byte-identical across runs" "$a" "$b"

# A crafted rule file must never execute. `$(...)` in a paths value is data.
cat >"$rules_repo/.claude/rules/evil.md" <<'EOF'
---
paths:
  - "$(touch /tmp/glob-tools-pwned)/**"
---

Command substitution in a paths value must be inert.
EOF
rm -f /tmp/glob-tools-pwned
git -C "$rules_repo" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$rules_repo" -c user.email=t@t -c user.name=t commit -qm evil >/dev/null 2>&1
run rules --root "$rules_repo" >/dev/null 2>&1
if [[ -e /tmp/glob-tools-pwned ]]; then
  fail "a crafted paths value does not execute" "no side effect" "command ran"
  rm -f /tmp/glob-tools-pwned
else
  pass "a crafted paths value does not execute"
fi

# --------------------------------------------------------------------------
# Non-git roots still answer
# --------------------------------------------------------------------------
plain="$(mktemp -d)"
mkdir -p "$plain/src"
printf 'x\n' >"$plain/src/a.ts"
out="$(run validate --root "$plain" --glob '**/*.ts')"
assert_eq "a non-git root falls back to a file walk" "1" "$(row_field "$out" '**/*.ts' 5)"

# --------------------------------------------------------------------------
rm -rf "$repo" "$repo_dot" "$repo_brace" "$repo_nested" "$repo_br" "$repo_esc" "$rules_repo" "$clean_repo" "$plain"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
