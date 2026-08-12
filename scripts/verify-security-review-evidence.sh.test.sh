#!/usr/bin/env bash
# Self-tests for verify-security-review-evidence.sh helpers.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATHS_FILE="$SCRIPT_DIR/../.github/claude-security-paths"
EVIDENCE_PATTERN='@anthropic-ai/claude-agent-sdk|mcp__github_inline_comment__create_inline_comment|Posted review|create_inline_comment|Claude Code action completed'
MIN_REVIEW_SECONDS=8

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }

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

log_has_execution_evidence() {
  grep -qE "$EVIDENCE_PATTERN" "$1" 2>/dev/null
}

# Kept byte-identical to the guard's own pattern. Anchored to runner annotation
# lines so the lane's echoed github-script SOURCE — which contains both phrases
# as string literals — cannot be mistaken for a real skip.
SKIP_ANNOTATION_PATTERN='##\[(warning|error)\].*(workflow-validation skip|class=skipped-validation)'

log_shows_validation_skip() {
  grep -qE "$SKIP_ANNOTATION_PATTERN" "$1" 2>/dev/null
}

would_reject_fast_success() {
  local duration="$1"
  local has_execution_evidence="$2"
  (( duration > 0 && duration < MIN_REVIEW_SECONDS && has_execution_evidence == 0 ))
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

if would_reject_fast_success 5 0; then
  pass "5s without evidence rejected"
else
  fail "5s without evidence rejected" "expected rejection"
fi

if would_reject_fast_success 5 1; then
  fail "5s with evidence accepted" "unexpected rejection"
else
  pass "5s with evidence accepted"
fi

if would_reject_fast_success 20 0; then
  fail "20s without evidence accepted (above floor)" "unexpected rejection"
else
  pass "20s without evidence accepted (above floor)"
fi

# Regression: the echoed github-script source of the lane's `Report review
# outcome` step, verbatim from run 31630114303 lines 1435 and 1437. The old
# unanchored pattern matched these and failed every successful in-scope PR.
# shellcheck disable=SC2016  # fixture is literal github-script source; ${lane} must not expand
printf '%s\n' \
  '    `${lane} concluded: ${outcome} class=skipped-validation with no ` +' \
  '      "(workflow-validation skip: the caller'"'"'s workflow file must " +' \
  >"$tmp_log"
if log_shows_validation_skip "$tmp_log"; then
  fail "echoed action source is not a validation skip" "unexpected match (#2337 false positive)"
else
  pass "echoed action source is not a validation skip"
fi

# True positive: the runner's rendered annotation for a real self-skip.
printf '%s\n' \
  '2026-08-12T18:46:14.6127175Z ##[warning]Claude security review concluded: success class=skipped-validation with no execution evidence — the action skipped itself before running (workflow-validation skip: the caller'"'"'s workflow file must match the default branch'"'"'s copy). Nothing was reviewed.' \
  >"$tmp_log"
if log_shows_validation_skip "$tmp_log"; then
  pass "annotated validation skip is detected"
else
  fail "annotated validation skip is detected" "expected match"
fi

# A clean run carries neither shape.
printf '%s\n' 'Installing @anthropic-ai/claude-agent-sdk' 'Claude Code action completed' >"$tmp_log"
if log_shows_validation_skip "$tmp_log"; then
  fail "clean lane log shows no validation skip" "unexpected match"
else
  pass "clean lane log shows no validation skip"
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
exit 1
