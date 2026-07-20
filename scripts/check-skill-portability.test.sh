#!/usr/bin/env bash
# Unit tests for check-skill-portability.sh. Synthetic cases run through --paths
# mode against files in a temp dir with a minimal single-pattern token list
# (SKILL_PORTABILITY_TOKENS); the exclusion case builds a synthetic plugins/ tree
# and runs the script's --all mode from a fixture root, exactly as the
# silent-skip suite does. Two cases run against the REAL corpus to prove the
# bare-vs-guarded discrimination on live files, not only synthetic ones.
# shellcheck disable=SC2016  # fixture bodies are literal skill content in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-skill-portability.sh"
REAL_TOKENS="$REPO_ROOT/scripts/skill-portability-tokens.txt"

# Minimal token list: just the active branch class, so a synthetic case is not
# coupled to the shipping list's staged entries.
TEST_TOKENS="$(mktemp)"
printf 'origin/(main|master)\n' >"$TEST_TOKENS"
trap 'rm -f "$TEST_TOKENS"' EXIT

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

# scan_paths <file>... — run the gate over explicit paths with the test tokens.
scan_paths() {
  SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash "$SCRIPT" --paths "$@"
}

tmpfile() {
  local f
  f="$(mktemp --suffix=.md)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

# --- bare origin/main fails with file:line ---------------------------------
f="$(tmpfile 'Base the diff on origin/main for the review.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "bare origin/main should fail, got success: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "bare origin/main fails with file:line"
else
  fail "expected COUPLING with file:line, got: $out"
fi
rm -f "$f"

# --- bare origin/master also fails -----------------------------------------
f="$(tmpfile 'git checkout -b feature origin/master')"
if scan_paths "$f" >/dev/null 2>&1; then
  fail "bare origin/master should fail"
else
  ok "bare origin/master fails"
fi
rm -f "$f"

# --- detection-ladder use (origin/HEAD fallback) passes --------------------
f="$(tmpfile 'git merge-base origin/HEAD HEAD (falling back to origin/main, then HEAD)')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "detection-first ladder passes (guarded)"
else
  fail "detection-ladder use should pass"
fi
rm -f "$f"

# --- generic presence prose does NOT guard a bare branch default -----------
f="$(tmpfile 'If using a rebase workflow, diff origin/main first.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "generic 'if using' prose must not guard a bare branch default: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "generic optional-dependency prose does not guard the active branch token"
else
  fail "expected line 1 flagged for bare origin/main under 'if using' prose, got: $out"
fi
rm -f "$f"

# --- the bare word "fallback" does NOT guard a bare branch default ----------
f="$(tmpfile 'As a fallback for a network timeout, run git diff origin/main.')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "standalone 'fallback' prose must not guard a bare branch default: $out"
elif echo "$out" | grep -q "COUPLING: ${f}:1:"; then
  ok "standalone 'fallback' prose does not guard the active branch token"
else
  fail "expected line 1 flagged for bare origin/main under 'fallback' prose, got: $out"
fi
rm -f "$f"

# --- a malformed active token fails closed (exit 2), not a silent pass ------
BAD_TOKENS="$(mktemp)"
printf 'origin/(main\n' >"$BAD_TOKENS" # unmatched '(' — invalid ERE, awk faults
f="$(tmpfile 'diff against origin/main here')"
SKILL_PORTABILITY_TOKENS="$BAD_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "malformed active token exits 2 (fail closed, no silent pass)"
else
  fail "malformed active token should exit 2, not silently treat the file as clean"
fi
rm -f "$f" "$BAD_TOKENS"

# --- same-line portability-ok annotation passes ----------------------------
f="$(tmpfile 'reset --hard origin/main <!-- portability-ok: fixture asserts the hardcode on purpose -->')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "same-line portability-ok passes"
else
  fail "same-line portability-ok should pass"
fi
rm -f "$f"

# --- portability-ok in the comment block above passes ----------------------
f="$(tmpfile '<!-- portability-ok: this reference is intentionally pinned -->
The base branch is origin/main here.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "comment-block-above portability-ok passes"
else
  fail "comment-block-above portability-ok should pass"
fi
rm -f "$f"

# --- annotation does not leak past intervening code ------------------------
f="$(tmpfile '<!-- portability-ok: covers only the next line -->
diff against origin/main here
now a plain line
diff against origin/main again')"
if out="$(scan_paths "$f" 2>&1)"; then
  fail "annotation should not sanction a later hit, got success: $out"
elif echo "$out" | grep -q ":4:" && ! echo "$out" | grep -q ":2:"; then
  ok "annotation covers line 2 only and does not leak past intervening code"
else
  fail "expected line 4 flagged and line 2 clean, got: $out"
fi
rm -f "$f"

# --- whole-file portability-scope declaration passes -----------------------
f="$(tmpfile '<!-- portability-scope: forge=github — inherent, declared boundary -->
This skill diffs origin/main and pushes with origin/master.')"
if scan_paths "$f" >/dev/null 2>&1; then
  ok "whole-file portability-scope passes"
else
  fail "whole-file portability-scope should pass"
fi
rm -f "$f"

# --- staged (commented) tokens stay inactive under the REAL token list -----
f="$(mktemp --suffix=.md)"
printf '%s\n' 'This agnostic skill mentions dotnet and raw.githubusercontent.com.' >"$f"
if SKILL_PORTABILITY_TOKENS="$REAL_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1; then
  ok "staged tokens (dotnet, raw.githubusercontent) are inactive in the shipped list"
else
  fail "shipped list should only enforce the active branch class"
fi
rm -f "$f"

# --- missing token list fails closed (exit 2) ------------------------------
f="$(tmpfile 'origin/main')"
SKILL_PORTABILITY_TOKENS="/nonexistent/tokens.txt" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "missing token list exits 2 (fail closed)"
else
  fail "missing token list should exit 2"
fi
rm -f "$f"

# --- an invalid base ref fails closed (exit 2) -----------------------------
(cd "$REPO_ROOT" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash "$SCRIPT" definitely-not-a-ref >/dev/null 2>&1)
if [[ "$?" -eq 2 ]]; then
  ok "invalid base ref exits 2 (fail closed)"
else
  fail "invalid base ref should exit 2"
fi

# --- --all excludes vendor/, evals/, and *.test.sh -------------------------
fx="$(mktemp -d)"
mkdir -p "$fx/scripts" "$fx/plugins/alpha/skills/x/vendor" "$fx/plugins/alpha/skills/x/evals"
cp "$SCRIPT" "$fx/scripts/"
printf 'diff against origin/main\n' >"$fx/plugins/alpha/skills/x/SKILL.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/vendor/upstream.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/evals/e.md"
printf 'origin/main\n' >"$fx/plugins/alpha/skills/x/gen.test.sh"
out="$(cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --all 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'skills/x/SKILL.md' &&
  ! echo "$out" | grep -qE 'vendor/|evals/|test\.sh'; then
  ok "--all scans SKILL.md but excludes vendor/, evals/, and *.test.sh"
else
  fail "--all exclusion set wrong (rc=$rc): $out"
fi
rm -rf "$fx"

# --- empty scope passes ----------------------------------------------------
fx="$(mktemp -d)"
mkdir -p "$fx/scripts" "$fx/plugins"
cp "$SCRIPT" "$fx/scripts/"
if (cd "$fx" && SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh --all >/dev/null 2>&1); then
  ok "empty skill tree passes"
else
  fail "empty skill tree should pass"
fi
rm -rf "$fx"

# --- diff-mode reads a Git-quoted (non-ASCII) changed path -----------------
# A changed file whose pathname triggers Git's C-style quoting (here a non-ASCII
# byte; core.quotePath defaults on) must still be gated. Without -z, git diff
# emits `"plugins/.../caf\303\251.md"`, the leading quote misses the
# plugins/*/skills/* glob, and the file is silently dropped — the silent
# exclusion the contract forbids. The fixture commits one ASCII-named and one
# non-ASCII-named coupling file, then diffs against the empty base commit: the
# ASCII hit proves -z left the common path intact, and two COUPLING lines prove
# the quoted path was read, not skipped. The non-ASCII name is built with octal
# escapes so this test source stays pure ASCII.
fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
quoted_name="$(printf 'caf\303\251.md')" # café.md in UTF-8 — non-ASCII, triggers Git quoting
out="$(
  cd "$fx" &&
    git init -q &&
    git config user.email test@example.com &&
    git config user.name test &&
    git commit -q --allow-empty -m base &&
    base="$(git rev-parse HEAD)" &&
    mkdir -p 'plugins/p/skills/s' &&
    printf 'diff against origin/main\n' >'plugins/p/skills/s/plain.md' &&
    printf 'diff against origin/main\n' >"plugins/p/skills/s/${quoted_name}" &&
    git add -A >/dev/null 2>&1 &&
    git commit -q -m add-skills &&
    SKILL_PORTABILITY_TOKENS="$TEST_TOKENS" bash scripts/check-skill-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'plain.md:1:' &&
  [[ "$(echo "$out" | grep -c 'COUPLING:')" -eq 2 ]]; then
  ok "diff-mode gates a Git-quoted (non-ASCII) changed path (not silently dropped)"
else
  fail "diff-mode should flag both the ASCII and non-ASCII coupling files (rc=$rc): $out"
fi
rm -rf "$fx"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
