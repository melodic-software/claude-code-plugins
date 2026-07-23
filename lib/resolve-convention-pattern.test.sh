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

# =====================================================================
# Neutral convention SSOT (convention_source pointer + flat-scalar YAML)
# =====================================================================

# Write a neutral YAML file at a repo-relative path inside repo $1.
addneutral() {
  local d="$1" path="$2" body="$3"
  mkdir -p "$d/$(dirname "$path")"
  printf '%s\n' "$body" >"$d/$path"
}

# --- pointer + single-quoted YAML value resolves ---
r="$(newrepo $'## convention_source\ndocs/conventions/commits.yml')"
addneutral "$r" "docs/conventions/commits.yml" $'# team commit convention\nsubject_pattern: \047^SW2-[0-9]+: .+\047'
assert_eq "neutral: quoted YAML subject" '^SW2-[0-9]+: .+' "$(run "$r")"

# --- double-quoted YAML value strips its quotes too ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'subject_pattern: "^DQ-[0-9]+: .+"'
assert_eq "neutral: double-quoted value" '^DQ-[0-9]+: .+' "$(run "$r")"

# --- unquoted YAML value passes through ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'subject_pattern: ^plain: .+'
assert_eq "neutral: unquoted value" '^plain: .+' "$(run "$r")"

# --- CC keyword works in the neutral file exactly as in markdown ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'subject_pattern: Conventional Commits'
assert_eq "neutral: CC keyword -> CC_ERE" "$CC_ERE" "$(run "$r")"

# --- pr_title deferral marker works in the neutral file ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'subject_pattern: \047^N-[0-9]+: .+\047\npr_title_pattern: Same as `subject_pattern`.'
assert_eq "neutral: pr deferral -> subject" '^N-[0-9]+: .+' "$(run "$r" pr_title_pattern)"

# --- dialect: posix-ere (explicit) still resolves ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'dialect: posix-ere\nsubject_pattern: \047^D-[0-9]+: .+\047'
assert_eq "neutral: dialect posix-ere ok" '^D-[0-9]+: .+' "$(run "$r")"

# --- dialect other than posix-ere -> no enforcement ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'dialect: pcre\nsubject_pattern: \047^\\d+: .+\047'
out="$(run "$r")"
rc=$?
assert_exit "neutral: dialect pcre -> exit 1" 1 "$rc"
assert_eq "neutral: dialect pcre -> empty stdout" "" "$out"

# --- declared pointer, missing file -> FAIL CLOSED (never markdown fallback) ---
r="$(newrepo $'## convention_source\nmissing.yml\n\n## subject_pattern\n^stale: .+')"
out="$(run "$r")"
rc=$?
assert_exit "neutral: missing file -> exit 1" 1 "$rc"
assert_eq "neutral: missing file -> empty (no stale markdown fallback)" "" "$out"

# --- absolute and traversal pointers are rejected ---
r="$(newrepo $'## convention_source\n/etc/conventions.yml')"
run "$r" >/dev/null 2>&1
assert_exit "neutral: absolute pointer -> exit 1" 1 $?
r="$(newrepo $'## convention_source\n../outside.yml')"
run "$r" >/dev/null 2>&1
assert_exit "neutral: traversal pointer -> exit 1" 1 $?

# --- a key the neutral file omits falls back to the team markdown H2 ---
r="$(newrepo $'## convention_source\nconventions.yml\n\n## pr_title_pattern\n^MD: .+')"
addneutral "$r" "conventions.yml" $'subject_pattern: \047^Y-[0-9]+: .+\047'
assert_eq "neutral: omitted key -> markdown fallback" '^MD: .+' "$(run "$r" pr_title_pattern)"

# --- neutral value WINS over a not-yet-retired markdown duplicate ---
r="$(newrepo $'## convention_source\nconventions.yml\n\n## subject_pattern\n^old-md: .+')"
addneutral "$r" "conventions.yml" $'subject_pattern: \047^new-yaml: .+\047'
assert_eq "neutral: YAML wins over markdown duplicate" '^new-yaml: .+' "$(run "$r")"

# --- comment and blank lines in the neutral file are inert ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'# convention SSOT\n\n# see CONTRIBUTING.md\nsubject_pattern: \047^C-[0-9]+: .+\047'
assert_eq "neutral: comments/blanks inert" '^C-[0-9]+: .+' "$(run "$r")"

# --- pointer in the LOCAL overlay only is ignored (team-only policy floor) ---
r="$(newrepo "" $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'subject_pattern: \047^evil: .+\047'
run "$r" >/dev/null 2>&1
assert_exit "neutral: overlay pointer ignored (team-only)" 1 $?

# --- a present-but-EMPTY neutral key fails closed (never stale markdown) ---
r="$(newrepo $'## convention_source\nconventions.yml\n\n## subject_pattern\n^stale-md: .+')"
addneutral "$r" "conventions.yml" $'subject_pattern: \047\047'
out="$(run "$r")"
rc=$?
assert_exit "neutral: empty quoted key -> exit 1" 1 "$rc"
assert_eq "neutral: empty quoted key -> empty stdout (no stale fallback)" "" "$out"
r="$(newrepo $'## convention_source\nconventions.yml\n\n## subject_pattern\n^stale-md: .+')"
addneutral "$r" "conventions.yml" $'subject_pattern:'
run "$r" >/dev/null 2>&1
assert_exit "neutral: bare empty key -> exit 1" 1 $?

# --- symlink escapes are rejected (skipped where ln -s can't make symlinks) ---
outside="$TEST_TMPDIR/outside.yml"
printf '%s\n' "subject_pattern: '^outside: .+'" >"$outside"
r="$(newrepo $'## convention_source\nlink.yml')"
ln -s "$outside" "$r/link.yml" 2>/dev/null
if [[ -L "$r/link.yml" ]]; then
  run "$r" >/dev/null 2>&1
  assert_exit "neutral: symlinked file rejected" 1 $?
  # A symlinked DIRECTORY segment escaping the repo is rejected too.
  mkdir -p "$TEST_TMPDIR/outdir"
  printf '%s\n' "subject_pattern: '^outdir: .+'" >"$TEST_TMPDIR/outdir/c.yml"
  r="$(newrepo $'## convention_source\nsub/c.yml')"
  ln -s "$TEST_TMPDIR/outdir" "$r/sub" 2>/dev/null
  if [[ -L "$r/sub" ]]; then
    run "$r" >/dev/null 2>&1
    assert_exit "neutral: symlinked dir segment rejected" 1 $?
  fi
else
  echo "SKIP: symlink cases (ln -s unavailable on this filesystem)"
fi

# =====================================================================
# Well-known default neutral path (docs/conventions/source-control/…)
# The resolver probes a repo-dogfooded default path when no explicit
# convention_source pointer is declared, so the common case reads ONE
# tool-agnostic file with no markdown pointer-parse. Precedence:
#   1. explicit convention_source pointer   (relocation override)
#   2. well-known docs/conventions/source-control/commit-convention.yml
#   3. markdown-H2 in .claude/source-control.md   (legacy)
# =====================================================================

WELL_KNOWN="docs/conventions/source-control/commit-convention.yml"

# --- well-known file present, NO pointer, NO markdown -> resolves from it ---
r="$(newrepo "")"
addneutral "$r" "$WELL_KNOWN" $'subject_pattern: \047^WK-[0-9]+: .+\047'
assert_eq "well-known: resolves with no pointer" '^WK-[0-9]+: .+' "$(run "$r")"

# --- well-known present AND markdown subject_pattern present -> well-known WINS (rung 2 > 3) ---
r="$(newrepo $'## subject_pattern\n^old-md: .+')"
addneutral "$r" "$WELL_KNOWN" $'subject_pattern: \047^wk-wins: .+\047'
assert_eq "well-known: wins over markdown H2" '^wk-wins: .+' "$(run "$r")"

# --- explicit pointer present AND well-known also present -> explicit WINS (rung 1 > 2) ---
r="$(newrepo $'## convention_source\nconventions.yml')"
addneutral "$r" "conventions.yml" $'subject_pattern: \047^explicit-wins: .+\047'
addneutral "$r" "$WELL_KNOWN" $'subject_pattern: \047^wk-loses: .+\047'
assert_eq "well-known: explicit pointer overrides well-known" '^explicit-wins: .+' "$(run "$r")"

# --- well-known present but broken (non-posix-ere dialect) -> fail closed ---
r="$(newrepo "")"
addneutral "$r" "$WELL_KNOWN" $'dialect: pcre\nsubject_pattern: \047^\\d+: .+\047'
out="$(run "$r")"
rc=$?
assert_exit "well-known: broken dialect -> exit 1" 1 "$rc"
assert_eq "well-known: broken dialect -> empty stdout" "" "$out"

# --- well-known present but empty key -> fail closed (never markdown fallback) ---
r="$(newrepo $'## subject_pattern\n^stale-md: .+')"
addneutral "$r" "$WELL_KNOWN" $'subject_pattern: \047\047'
out="$(run "$r")"
rc=$?
assert_exit "well-known: empty key -> exit 1 (no stale markdown)" 1 "$rc"
assert_eq "well-known: empty key -> empty stdout" "" "$out"

# --- NO well-known, NO pointer, markdown present -> markdown (back-compat rung 3) ---
r="$(newrepo $'## subject_pattern\n^md-only: .+')"
assert_eq "well-known: absent -> markdown back-compat" '^md-only: .+' "$(run "$r")"

# --- well-known: a key it omits falls back to markdown H2 (per-key) ---
r="$(newrepo $'## pr_title_pattern\n^MDPR: .+')"
addneutral "$r" "$WELL_KNOWN" $'subject_pattern: \047^WKS-[0-9]+: .+\047'
assert_eq "well-known: omitted key -> markdown fallback" '^MDPR: .+' "$(run "$r" pr_title_pattern)"

# --- usage / invalid key ---
bash "$SCRIPT" >/dev/null 2>&1
assert_exit "no args -> exit 2" 2 $?
bash "$SCRIPT" "$TEST_TMPDIR" bogus_key >/dev/null 2>&1
assert_exit "invalid key -> exit 2" 2 $?

echo ""
echo "ran $CASE_NUM cases, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
