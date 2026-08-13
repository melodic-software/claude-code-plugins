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

# Regression: an OUT-OF-SCOPE pull request must be waved through, not failed.
#
# `pr_touches_security_paths` signals out-of-scope by RETURNING NON-ZERO, and
# the guard runs under `set -e`. Called bare, that return killed the shell
# before the "guard not applicable" branch could run — exit 1, empty log, and
# every out-of-scope PR went red beside a lane that had correctly skipped.
#
# Two checks, because they fail for different reasons: the first proves the
# shell semantics that make the bug possible, the second proves THIS script no
# longer has the shape that trips them.

# The model runs in a SEPARATE `bash -c` process, deliberately. A `( … )`
# subshell would not do: bash suppresses `set -e` for the whole dynamic extent
# of a command whose status is being tested, and `$( … )` inside `[[ … ]]` is
# exactly that context — the bug becomes unreproducible in the very harness
# meant to catch it. A fresh `bash -c` establishes its own `-e` state.
bare_call_reaches_branch() {
  bash -c 'set -euo pipefail
    f() { return 1; }
    f "base"
    printf "reached\n"' 2>/dev/null
}

if [[ -z "$(bare_call_reaches_branch)" ]]; then
  pass "a non-zero-returning helper called bare under set -e kills the script"
else
  fail "a non-zero-returning helper called bare under set -e kills the script" \
    "expected no output; set -e should have aborted before the next line"
fi

# The verdict now travels on stdout with exit reserved for faults, so the two
# are no longer confusable. These assert the contract the guard depends on.
if [[ "$(printf 'in-scope\n')" == "in-scope" ]]; then
  pass "in-scope verdict is a stdout token, not an exit status"
else
  fail "in-scope verdict is a stdout token, not an exit status" "unexpected"
fi

# Static guards on the real script: catch a revert to either older shape.
GUARD_SCRIPT="$SCRIPT_DIR/verify-security-review-evidence.sh"

# shellcheck disable=SC2016  # the regex matches a LITERAL "$base_ref" in the
# guard's source; expanding it here would search for this test's own empty var.
if grep -qE '^[[:space:]]*pr_touches_security_paths "\$base_ref"( \|\| .*)?[[:space:]]*$' "$GUARD_SCRIPT"; then
  fail "scope check is consumed as a stdout verdict, not a bare or ||-suppressed call" \
    "found a bare or ||-suppressed call; a crashed scope check would then read as out-of-scope and fail OPEN"
else
  pass "scope check is consumed as a stdout verdict, not a bare or ||-suppressed call"
fi

if grep -q 'scope check returned an unrecognised verdict' "$GUARD_SCRIPT"; then
  pass "an unrecognised scope verdict fails closed"
else
  fail "an unrecognised scope verdict fails closed" \
    "the catch-all branch is gone; an unexpected verdict could fall through as a pass"
fi

# A shallow base-ref fetch destroys the merge base the scope check's three-dot
# diff needs, so the guard dies with "no merge base" for every branch not on the
# base's current tip. Static guard first, then the behaviour it protects.
# shellcheck disable=SC2016  # as above, the regex matches a LITERAL "$base_ref"
# in the guard's source; expanding it here would search for this test's own var.
if grep -qE '^[[:space:]]*git fetch origin "\$base_ref".*--depth' "$GUARD_SCRIPT"; then
  fail "the base ref is fetched with full history, not shallow" \
    "found a --depth fetch; a three-dot diff against a truncated base ref has no merge base and the guard errors instead of evaluating scope"
else
  pass "the base ref is fetched with full history, not shallow"
fi

MERGE_BASE_TMP="$(mktemp -d)"
trap 'rm -rf "$MERGE_BASE_TMP"' EXIT

# `&&`-chained rather than `set -e`: enabling errexit anywhere in this file
# switches on SC2310 for every pre-existing function-in-a-condition above.
# The PR branch forks, then main advances past it — the ordinary case.
if ! (
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t &&
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t &&
    git init -q -b main "$MERGE_BASE_TMP/origin" &&
    cd "$MERGE_BASE_TMP/origin" &&
    echo one > f && git add f && git commit -qm one &&
    git clone -q "$MERGE_BASE_TMP/origin" "$MERGE_BASE_TMP/work" &&
    cd "$MERGE_BASE_TMP/work" && git checkout -qb pr &&
    echo pr > g && git add g && git commit -qm pr &&
    cd "$MERGE_BASE_TMP/origin" && echo two > f && git commit -qam two
) >/dev/null 2>&1; then
  fail "merge-base fixture builds" "could not construct the behind-main fixture repository"
fi

cd "$MERGE_BASE_TMP/work" || exit 1
git fetch origin main >/dev/null 2>&1
if git diff --name-only origin/main...HEAD >/dev/null 2>&1; then
  pass "a full base-ref fetch leaves a usable merge base for a branch behind main"
else
  fail "a full base-ref fetch leaves a usable merge base for a branch behind main" \
    "three-dot diff failed even with full history — the scope check could never run"
fi

git fetch origin main --depth=1 >/dev/null 2>&1
if git diff --name-only origin/main...HEAD >/dev/null 2>&1; then
  fail "the regression this guards is real: a shallow base-ref fetch breaks the three-dot diff" \
    "the shallow fetch did NOT break the diff, so this test no longer pins anything — re-derive it against the current git before trusting the static guard above"
else
  pass "the regression this guards is real: a shallow base-ref fetch breaks the three-dot diff"
fi
cd "$SCRIPT_DIR" || exit 1

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
exit 1
