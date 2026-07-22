#!/usr/bin/env bash
# Regression tests for lib/resolve-convention-pattern.sh — the shared commit/PR
# convention ENFORCEMENT-pattern resolver. Run: bash lib/resolve-convention-pattern.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-convention-pattern.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: [$2], actual: [$3]"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}

# The canonical Conventional Commits ERE — kept in lockstep with the SUT header.
CC_ERE='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+'

# Make an isolated repo root whose TEAM layer holds the given markdown body.
# Extra positional args after the first write additional overlay files:
#   newrepo "<team body>" [local-body] [does NOT create user-global — see note]
newrepo() {
  local d
  d="$(mktemp -d "$TEST_TMPDIR/repo.XXXXXX")"
  mkdir -p "$d/.claude"
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" >"$d/.claude/source-control.md"
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >"$d/.claude/source-control.local.md"
  printf '%s' "$d"
}
run() { bash "$SCRIPT" "$1" "${2:-subject_pattern}"; }

# --- --help ---
out="$(bash "$SCRIPT" --help)"
assert_exit "--help exits 0" 0 $?

# --- Conventional Commits keyword expands to the canonical ERE ---
r="$(newrepo $'## subject_pattern\nConventional Commits')"
assert_eq "CC keyword -> CC_ERE" "$CC_ERE" "$(run "$r")"

# --- self-describing preamble above the first H2 is inert (setup template) ---
# /source-control:setup apply writes a prose header for non-plugin readers; the
# parse contract reads only the first non-empty body line under the `## <key>`
# H2, so a file with the preamble must resolve identically to one without.
r="$(newrepo $'# source-control configuration\n\nRead by the source-control Claude Code plugin (and, where installed, the\nguardrails commit-convention gate). Without those plugins this file is inert.\nIt is a drafting aid, not team-wide enforcement.\n\n## subject_pattern\nConventional Commits')"
assert_eq "preamble above first H2 is inert" "$CC_ERE" "$(run "$r")"

# --- a custom ERE passes through unchanged ---
r="$(newrepo $'## subject_pattern\n^[A-Z]+-[0-9]+: .+')"
assert_eq "plain ERE unchanged" '^[A-Z]+-[0-9]+: .+' "$(run "$r")"

# --- an already-alternated ERE passes through unchanged ---
r="$(newrepo $'## subject_pattern\n^(feat|fix): .+')"
assert_eq "ERE alternation unchanged" '^(feat|fix): .+' "$(run "$r")"

# --- PCRE-only constructs are NOT translated -> no enforcement ---
# The resolver accepts POSIX ERE and rejects PCRE; a team writes [0-9] not \d.
r="$(newrepo $'## subject_pattern\n^(?:feat|fix): .+')"
run "$r" >/dev/null 2>&1
assert_exit "(?: non-capturing group -> exit 1" 1 $?
r="$(newrepo $'## subject_pattern\n^[A-Z]+-\\d+: .+')"
run "$r" >/dev/null 2>&1
assert_exit "\\d -> exit 1 (use [0-9])" 1 $?
r="$(newrepo $'## subject_pattern\n^\\w+\\s: .+')"
run "$r" >/dev/null 2>&1
assert_exit "\\w \\s -> exit 1" 1 $?

# --- lookahead has no ERE equivalent -> no enforcement, exit 1, empty stdout ---
r="$(newrepo $'## subject_pattern\n^(?=.{1,50}$)\\w+: .+')"
out="$(run "$r")"
rc=$?
assert_exit "lookaround -> exit 1" 1 "$rc"
assert_eq "lookaround -> empty stdout" "" "$out"

# --- word-boundary \b is non-ERE -> no enforcement ---
r="$(newrepo $'## subject_pattern\n^\\bfeat: .+')"
run "$r" >/dev/null 2>&1
assert_exit "\\b -> exit 1" 1 $?

# --- backreference is non-ERE -> no enforcement ---
r="$(newrepo $'## subject_pattern\n^(\\w+): \\1')"
run "$r" >/dev/null 2>&1
assert_exit "backref -> exit 1" 1 $?

# --- negated shorthand classes (\D \S \W) have no ERE spelling -> no enforce ---
r="$(newrepo $'## subject_pattern\n^\\D+: .+')"
run "$r" >/dev/null 2>&1
assert_exit "\\D -> exit 1" 1 $?

# --- absolute anchors (\A \z \Z) are non-ERE -> no enforcement ---
r="$(newrepo $'## subject_pattern\n\\Afeat: .+\\z')"
run "$r" >/dev/null 2>&1
assert_exit "\\A \\z -> exit 1" 1 $?

# --- control-char escapes (\t \n ...) are non-ERE -> no enforcement ---
r="$(newrepo $'## subject_pattern\n^\\tJIRA-[0-9]+: .+')"
run "$r" >/dev/null 2>&1
assert_exit "\\t -> exit 1" 1 $?

# --- an escaped backslash (\\d = literal, not the class) -> no enforcement ---
r="$(newrepo $'## subject_pattern\n^foo\\\\d: .+')"
run "$r" >/dev/null 2>&1
assert_exit "escaped backslash -> exit 1" 1 $?

# --- a \d/\w/\s shorthand INSIDE a bracket expression -> no enforcement ---
r="$(newrepo $'## subject_pattern\n^[\\w-]+: .+')"
run "$r" >/dev/null 2>&1
assert_exit "shorthand inside bracket -> exit 1" 1 $?

# --- a pattern that does not compile as POSIX ERE -> no enforcement (net) ---
r="$(newrepo $'## subject_pattern\n^[: .+')"
out="$(run "$r")"
rc=$?
assert_exit "uncompilable ERE -> exit 1" 1 "$rc"
assert_eq "uncompilable ERE -> empty stdout" "" "$out"

# --- unresolved: no team file at all -> exit 1, NEVER the CC default ---
r="$(newrepo "")"
out="$(run "$r")"
rc=$?
assert_exit "no team file -> exit 1" 1 "$rc"
assert_eq "no team file -> empty (no CC fallback)" "" "$out"

# --- unresolved: file exists but key absent -> exit 1 ---
r="$(newrepo $'## trailer_policy\nnone')"
run "$r" >/dev/null 2>&1
assert_exit "key absent -> exit 1" 1 $?

# --- policy-floor: a LOCAL overlay pattern is IGNORED by enforcement ---
# team file absent, overlay present -> still no enforcement (gate is team-only).
r="$(newrepo "" $'## subject_pattern\n^anything: .+')"
run "$r" >/dev/null 2>&1
assert_exit "local overlay never enforces (team-only)" 1 $?

# --- pr_title_pattern deferral resolves the effective subject pattern ---
r="$(newrepo $'## subject_pattern\n^ABC-[0-9]+: .+\n\n## pr_title_pattern\nSame as `subject_pattern`.')"
assert_eq "pr deferral -> subject" '^ABC-[0-9]+: .+' "$(run "$r" pr_title_pattern)"

# --- pr_title_pattern with its own value stands alone ---
r="$(newrepo $'## subject_pattern\n^X: .+\n\n## pr_title_pattern\n^PR: .+')"
assert_eq "pr explicit value" '^PR: .+' "$(run "$r" pr_title_pattern)"

# --- first non-empty body line wins; leading blank lines skipped ---
r="$(newrepo $'## subject_pattern\n\n^spaced: .+')"
assert_eq "blank line before value skipped" '^spaced: .+' "$(run "$r")"

# --- usage / invalid key ---
bash "$SCRIPT" >/dev/null 2>&1
assert_exit "no args -> exit 2" 2 $?
bash "$SCRIPT" "$TEST_TMPDIR" bogus_key >/dev/null 2>&1
assert_exit "invalid key -> exit 2" 2 $?

echo ""
echo "ran $CASE_NUM cases, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
