#!/usr/bin/env bash
# Self-tests for verify-security-review-evidence.sh helpers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATHS_FILE="$SCRIPT_DIR/../.github/claude-security-paths"
EVIDENCE_PATTERN='@anthropic-ai/claude-agent-sdk|mcp__github_inline_comment__create_inline_comment|Posted review|create_inline_comment|Claude Code action completed'
MIN_REVIEW_SECONDS=8
FAST_NO_EVIDENCE_CEILING_SECONDS=45

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }

log_has_execution_evidence() {
  grep -qE "$EVIDENCE_PATTERN" "$1" 2>/dev/null
}

would_reject_fast_success() {
  local duration="$1"
  local has_execution_evidence="$2"
  if (( duration > 0 && duration < MIN_REVIEW_SECONDS )); then
    return 0
  fi
  if (( duration > 0 && duration < FAST_NO_EVIDENCE_CEILING_SECONDS && has_execution_evidence == 0 )); then
    return 0
  fi
  return 1
}

matches_paths() {
  local paths_file="$1"
  shift
  python3 - "$paths_file" "$@" <<'PY'
import fnmatch
import re
import sys

paths_file = sys.argv[1]
patterns = []
with open(paths_file, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)

def pattern_matches(path: str, pat: str) -> bool:
    if fnmatch.fnmatch(path, pat):
        return True
    if pat.endswith("/**"):
        prefix = pat[:-3].replace("*", "[^/]*")
        if re.match("^" + prefix + ".*", path):
            return True
    if pat.startswith("**/"):
        suffix = pat[3:]
        if fnmatch.fnmatch(path, "*" + suffix) or path.endswith(suffix.lstrip("*")):
            return True
    if pat == "**/*.sh" and path.endswith(".sh"):
        return True
    norm = pat.replace("**/", "*/").replace("/**", "/*")
    return fnmatch.fnmatch(path, norm)

for path in sys.argv[2:]:
    for pat in patterns:
        if pattern_matches(path, pat):
            sys.exit(0)
sys.exit(1)
PY
}

if matches_paths "$PATHS_FILE" "plugins/guardrails/hooks/block-hook-bypass.sh"; then
  pass "guardrails hook path is security-relevant"
else
  fail "guardrails hook path is security-relevant" "expected match"
fi

if matches_paths "$PATHS_FILE" "docs/README.md"; then
  fail "docs-only path is not security-relevant" "unexpected match"
else
  pass "docs-only path is not security-relevant"
fi

tmp_log="$(mktemp)"
trap 'rm -f "$tmp_log"' EXIT

printf '%s\n' 'Installing @anthropic-ai/claude-agent-sdk' >"$tmp_log"
if log_has_execution_evidence "$tmp_log"; then
  pass "fixture log with SDK marker counts as execution evidence"
else
  fail "fixture log with SDK marker counts as execution evidence" "expected match"
fi

printf '%s\n' 'checkout complete' 'job finished' >"$tmp_log"
if log_has_execution_evidence "$tmp_log"; then
  fail "fixture log without markers lacks execution evidence" "unexpected match"
else
  pass "fixture log without markers lacks execution evidence"
fi

if would_reject_fast_success 5 1; then
  pass "5s always rejected (absolute floor)"
else
  fail "5s always rejected (absolute floor)" "expected rejection"
fi

if would_reject_fast_success 20 0; then
  pass "20s without evidence rejected"
else
  fail "20s without evidence rejected" "expected rejection"
fi

if would_reject_fast_success 20 1; then
  fail "20s with evidence accepted" "unexpected rejection"
else
  pass "20s with evidence accepted"
fi

if would_reject_fast_success 50 0; then
  fail "50s without evidence accepted (above ceiling)" "unexpected rejection"
else
  pass "50s without evidence accepted (above ceiling)"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
exit 1
