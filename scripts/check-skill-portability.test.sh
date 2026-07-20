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
elif echo "$out" | grep -q ":4:"; then
  ok "annotation does not leak past intervening code"
else
  fail "expected only line 4 flagged, got: $out"
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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
