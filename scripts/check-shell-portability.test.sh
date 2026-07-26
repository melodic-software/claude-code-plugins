#!/usr/bin/env bash
# portability-scope: this suite IS check-shell-portability.sh's own fixture
# corpus and necessarily contains, as literal test data, the GNU-only
# constructs the gate detects (\b, unsuffixed sed -i, grep -P, etc.) — the
# whole-file declaration this gate itself defines (see the script header's
# escape #3), exercised on itself the way check-skill-portability.sh's own
# STAGED-class self-reference exercises its sibling mechanism.
#
# Unit tests for check-shell-portability.sh. Synthetic cases run through
# --paths mode with a minimal, class-scoped token list
# (SHELL_PORTABILITY_TOKENS) built per test so a fixture is never coupled to
# the shipping list's other active classes; two cases run against the REAL
# shipped token list and the REAL corpus — the known-good markdown-format.sh
# reference implementation, and the shipping list's staged-class inertness —
# to prove the shipping config, not just the mechanism.
#
# Bespoke PASS/FAIL counters by design, not drift: this is repo tooling, not a
# plugin, so no plugin assertion library applies here — see
# docs/conventions/shell-test-helpers/README.md.
# shellcheck disable=SC2016  # fixture bodies are literal shell content in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-shell-portability.sh"
REAL_TOKENS="$REPO_ROOT/scripts/shell-portability-tokens.txt"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

# scan_paths <tokens-file> <file>... — run the gate over explicit paths.
scan_paths() {
  local tokens="$1"
  shift
  SHELL_PORTABILITY_TOKENS="$tokens" bash "$SCRIPT" --paths "$@"
}

# one_token_list <ere-pattern> — a temp token file with exactly one active
# pattern, so a synthetic case is not coupled to any other class.
one_token_list() {
  local f
  f="$(mktemp)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

tmpsh() {
  local f
  f="$(mktemp --suffix=.sh)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

# escape_token <esc> — builds the shipped grep/sed-context-required ERE for
# one regex-escape class, matching scripts/shell-portability-tokens.txt's
# active pattern shape exactly (kept here rather than sourced, so a fixture
# is not coupled to the shipping list's other active classes).
escape_token() {
  local esc="$1"
  printf '(grep|sed)[^\\n]*%s|%s[^\\n]*(grep|sed)' "$esc" "$esc"
}

# =============================================================================
# Regex-escape classes (\b \< \> \s \S \w \W) — the exact near-miss family.
# =============================================================================

# --- literal \b fires, and awk actually resolves it (the repo's own sibling
# token list documents that on gawk AND mawk/nawk, \b matches a literal
# backspace BYTE, not a boundary, when used as a boundary anchor — verify the
# LITERAL-TWO-CHARACTER-SEQUENCE form this gate uses is not silently inert
# under whichever awk resolves on the runner) -------------------------------
tok="$(one_token_list "$(escape_token '\\b')")"
f="$(tmpsh "grep -Eq '\\brequire\\b' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "literal \\\\b in a grep pattern should fail, got success: $out"
elif echo "$out" | grep -q "PORTABILITY: ${f}:1:"; then
  ok "literal \\\\b in a grep pattern is detected (not silently inert)"
else
  fail "expected PORTABILITY with file:line, got: $out"
fi
rm -f "$f"

# --- the POSIX-portable bracket-expression replacement does NOT fire -------
f="$(tmpsh 'grep -Eq "(^|[^A-Za-z0-9_\$])require($|[^A-Za-z0-9_\$])" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "the bracket-expression word-boundary replacement does not fire"
else
  fail "the POSIX-portable replacement must not be flagged"
fi
rm -f "$f"

# --- a co-located printf/$'...' use of the SAME two characters is NOT
# regex-pattern syntax and must not fire, even though it is not inside a
# grep/sed invocation on this line (confirmed against a real shell: printf
# '\b' emits an actual backspace byte, on GNU and BSD alike) ----------------
f="$(tmpsh "printf '\\bspinner-frame\\n'")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "printf '\\b' (no grep/sed on the line) is not flagged"
else
  fail "printf '\\b' must not be flagged -- it is portable escape-sequence syntax, not a regex pattern"
fi
rm -f "$f" "$tok"

# --- \s \w \S \W \< \> each fire individually, only with grep/sed context --
for esc in '\\s' '\\S' '\\w' '\\W' '\\<' '\\>'; do
  tok="$(one_token_list "$(escape_token "$esc")")"
  f="$(tmpsh "sed -E 's/${esc}foo${esc}/bar/' \"\$file\"")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "literal $esc should fail, got success: $out"
  elif echo "$out" | grep -q "PORTABILITY:"; then
    ok "literal $esc is detected"
  else
    fail "expected PORTABILITY for $esc, got: $out"
  fi
  rm -f "$f" "$tok"
done

# =============================================================================
# grep -P / --perl-regexp
# =============================================================================

tok="$(one_token_list 'grep[^\n]*[[:space:]]-[A-Za-z]*P[A-Za-z]*([[:space:]]|$)')"

f="$(tmpsh 'grep -P "\\d+" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "grep -P should fail, got success: $out"
else
  ok "grep -P is detected"
fi
rm -f "$f"

f="$(tmpsh 'grep -riP "\\d+" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "grep -riP (combined flags, P last) should fail"
else
  ok "grep -riP (combined flags, P last) is detected"
fi
rm -f "$f"

# --- P need not be the LAST letter in the flag cluster --------------------
f="$(tmpsh 'grep -Pn "\\d+" "$file"')" # spellchecker:disable-line
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "grep -Pn (P not last in the cluster) should fail" # spellchecker:disable-line
else
  ok "grep -Pn (P not last in the cluster) is detected" # spellchecker:disable-line
fi
rm -f "$f"

f="$(tmpsh '# Cross-platform: uses grep -E (POSIX ERE) only -- no grep -P (macOS lacks it).')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a comment merely naming grep -P is not flagged (construct matching skips comments)"
else
  fail "a comment-only mention of grep -P must not fire"
fi
rm -f "$f" "$tok"

# =============================================================================
# echo -e / sort -V
# =============================================================================

tok="$(one_token_list 'echo[[:space:]]+-[a-zA-Z]*e[a-zA-Z]*([[:space:]]|$)')"

f="$(tmpsh 'echo -e "line1\nline2"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "echo -e should fail, got success: $out"
else
  ok "echo -e is detected"
fi
rm -f "$f"

# --- e need not be the only letter in the cluster ("echo -ne") -------------
f="$(tmpsh "echo -ne 'a\\nb'")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "echo -ne (combined flags) should fail"
else
  ok "echo -ne (combined flags) is detected"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'sort[^\n]*[[:space:]]-[A-Za-z]*V[A-Za-z]*([[:space:]]|$)')"

f="$(tmpsh 'sort -V "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sort -V should fail, got success: $out"
else
  ok "sort -V is detected"
fi
rm -f "$f"

# --- V need not be the LAST letter in the flag cluster ("sort -Vr") --------
f="$(tmpsh 'sort -Vr "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "sort -Vr (V not last in the cluster) should fail"
else
  ok "sort -Vr (V not last in the cluster) is detected"
fi
rm -f "$f" "$tok"

# --- the --version-sort long form is a separate literal token -------------
tok="$(one_token_list '--version-sort')"
f="$(tmpsh 'sort --version-sort "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sort --version-sort should fail, got success: $out"
else
  ok "sort --version-sort (long form) is detected"
fi
rm -f "$f" "$tok"

# =============================================================================
# sed -i without a backup-suffix argument
# =============================================================================

tok="$(one_token_list 'sed[^\n]*-i[[:space:]]+[^[:space:]]')"

f="$(tmpsh "sed -i 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "unsuffixed sed -i should fail, got success: $out"
else
  ok "unsuffixed sed -i is detected"
fi
rm -f "$f"

f="$(tmpsh "sed -i.bak -E \"s/foo/bar/\" \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -i.bak (suffix directly attached) is not flagged"
else
  fail "sed -i.bak must not be flagged"
fi
rm -f "$f"

# --- the space-separated empty-suffix idiom (-i '' / -i "") is NOT the
# portable form it looks like -- verified against a real GNU sed 4.9, that
# exact invocation exits 2 (the empty string is consumed as sed's SCRIPT
# argument, not as -i's suffix), so it must stay flagged, not be excused.
f="$(tmpsh "sed -i '' 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -i '' should fail -- it is GNU-incompatible despite looking BSD-safe, got success: $out"
else
  ok "sed -i '' (space-separated empty-suffix, single-quoted) is detected, not excused"
fi
rm -f "$f"

f="$(tmpsh 'sed -i "" -E "s/foo/bar/" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -i \"\" should fail -- it is GNU-incompatible despite looking BSD-safe, got success: $out"
else
  ok "sed -i \"\" (space-separated empty-suffix, double-quoted) is detected, not excused"
fi
rm -f "$f" "$tok"

# =============================================================================
# readlink -f / --canonicalize, auto-guarded by a co-located realpath attempt
# =============================================================================

tok="$(one_token_list 'readlink[[:space:]]+(-[A-Za-z]*f|--canonicalize)')"

f="$(tmpsh 'resolved=$(readlink -f -- "$1" 2>/dev/null)')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "bare readlink -f should fail, got success: $out"
else
  ok "bare readlink -f (no realpath attempt) is detected"
fi
rm -f "$f"

f="$(tmpsh 'resolved=$(realpath -- "$1" 2>/dev/null) || resolved=$(readlink -f -- "$1" 2>/dev/null)')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "readlink -f co-located with a realpath attempt is auto-guarded"
else
  fail "the realpath-first fallback ladder must not be flagged"
fi
rm -f "$f"

# --- mere co-location is not enough -- the guard requires an actual `||`
# fallback relationship. Two unconditional statements (semicolon-separated,
# no ||) both mentioning realpath/readlink on one line must still flag: the
# GNU-only readlink -f call runs unconditionally regardless of what realpath
# did, so there is no real fallback protecting it.
f="$(tmpsh 'realpath -- "$1" >/dev/null; readlink -f -- "$1"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "realpath;readlink with no || fallback relationship should fail, got success: $out"
else
  ok "realpath and readlink with no actual || fallback relationship is still flagged"
fi
rm -f "$f" "$tok"

# --- the realpath guard is scoped to the readlink pattern, not the whole line
# A line mentioning "realpath" for an unrelated reason must not blanket-excuse
# a DIFFERENT active token's hit on that same line.
tok="$(one_token_list "$(printf '%s\n%s' '\\b' 'readlink[[:space:]]+(-[A-Za-z]*f|--canonicalize)')")"
f="$(tmpsh 'echo "realpath is a coreutils tool"; grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "an unrelated realpath mention should not excuse the \\b hit, got success: $out"
else
  ok "the realpath guard is scoped to the readlink pattern, not the whole line"
fi
rm -f "$f" "$tok"

# =============================================================================
# Opt-out annotation
# =============================================================================

tok="$(one_token_list '\\b')"

f="$(tmpsh "grep -Eq '\\bfoo\\b' \"\$file\" # portability-ok: fixture asserts the GNU-only form on purpose")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "same-line portability-ok passes"
else
  fail "same-line portability-ok should pass"
fi
rm -f "$f"

f="$(tmpsh '# portability-ok: this fixture is intentionally GNU-only
grep -Eq "\\bfoo\\b" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "comment-block-above portability-ok passes"
else
  fail "comment-block-above portability-ok should pass"
fi
rm -f "$f"

f="$(tmpsh '# portability-ok: covers only the next line
grep -Eq "\\bfoo\\b" "$file"
plain_line=1
grep -Eq "\\bbar\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "annotation should not sanction a later hit, got success: $out"
elif echo "$out" | grep -q ":4:" && ! echo "$out" | grep -q ":2:"; then
  ok "annotation covers line 2 only and does not leak past intervening code"
else
  fail "expected line 4 flagged and line 2 clean, got: $out"
fi
rm -f "$f" "$tok"

# --- whole-file portability-scope declaration excuses every hit ------------
tok="$(one_token_list '\\b')"
f="$(tmpsh '# portability-scope: this fixture IS a GNU-only-construct corpus, on purpose
grep -Eq "\\bfoo\\b" "$file"
grep -Eq "\\bbar\\b" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "whole-file portability-scope excuses every hit in the file"
else
  fail "whole-file portability-scope should pass"
fi
rm -f "$f" "$tok"

# =============================================================================
# Fail-closed behavior
# =============================================================================

BAD_TOKENS="$(mktemp)"
printf '%s\n' '(unterminated' >"$BAD_TOKENS" # unmatched '(' -- invalid ERE, awk faults
f="$(tmpsh 'grep -Eq foo bar')"
SHELL_PORTABILITY_TOKENS="$BAD_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "malformed active token exits 2 (fail closed, no silent pass)"
else
  fail "malformed active token should exit 2, not silently treat the file as clean"
fi
rm -f "$f" "$BAD_TOKENS"

f="$(tmpsh 'grep -Eq foo bar')"
SHELL_PORTABILITY_TOKENS="/nonexistent/tokens.txt" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "missing token list exits 2 (fail closed)"
else
  fail "missing token list should exit 2"
fi
rm -f "$f"

(cd "$REPO_ROOT" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash "$SCRIPT" definitely-not-a-ref >/dev/null 2>&1)
if [[ "$?" -eq 2 ]]; then
  ok "invalid base ref exits 2 (fail closed)"
else
  fail "invalid base ref should exit 2"
fi

# =============================================================================
# Scope resolution: --all excludes vendor/, non-.sh files stay out of scope
# =============================================================================

fx="$(mktemp -d)"
mkdir -p "$fx/scripts" "$fx/plugins/alpha/vendor"
cp "$SCRIPT" "$fx/scripts/"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/gate.sh"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/vendor/upstream.sh"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/notes.md" # non-.sh stays out of scope
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'gate.sh' &&
  ! echo "$out" | grep -qE 'vendor/|notes\.md'; then
  ok "--all scans gate.sh but excludes vendor/ and non-.sh files"
else
  fail "--all exclusion set wrong (rc=$rc): $out"
fi
rm -rf "$fx"

fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
if (cd "$fx" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all >/dev/null 2>&1); then
  ok "an empty tree passes"
else
  fail "an empty tree should pass"
fi
rm -rf "$fx"

# --- diff-mode reads a Git-quoted (non-ASCII) changed path -----------------
fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
quoted_name="$(printf 'quoted-\303\251.sh')" # trailing U+00E9 byte -- non-ASCII, triggers Git quoting
out="$(
  cd "$fx" &&
    git init -q &&
    git config user.email test@example.com &&
    git config user.name test &&
    git commit -q --allow-empty -m base &&
    base="$(git rev-parse HEAD)" &&
    printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >'plain.sh' &&
    printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$quoted_name" &&
    git add -A >/dev/null 2>&1 &&
    git commit -q -m add-scripts &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'plain.sh:1:' &&
  [[ "$(echo "$out" | grep -c 'PORTABILITY:')" -eq 2 ]]; then
  ok "diff-mode gates a Git-quoted (non-ASCII) changed path (not silently dropped)"
else
  fail "diff-mode should flag both the ASCII and non-ASCII changed files (rc=$rc): $out"
fi
rm -rf "$fx"

# =============================================================================
# The shipped token list against the REAL corpus
# =============================================================================

# --- the reference implementation this issue names as known-good is clean --
if out="$(scan_paths "$REAL_TOKENS" "$REPO_ROOT/plugins/markdown-format/hooks/markdown-format.sh" 2>&1)"; then
  ok "the shipped token list does not flag markdown-format.sh's reference implementation"
else
  fail "markdown-format.sh must stay clean under the shipped token list, got: $out"
fi

# --- staged (commented) classes stay inactive under the shipped list -------
f="$(tmpsh 'x=$(date -d "$s" +%s); y=$(stat -c%s "$f"); t=$(mktemp -p "$d")')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "staged classes (date -d, stat -c, mktemp -p) are inactive in the shipped list"
else
  fail "shipped list should only enforce the active classes"
fi
rm -f "$f"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
