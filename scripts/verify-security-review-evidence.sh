#!/usr/bin/env bash
# verify-security-review-evidence.sh — fail-closed guard for the required
# security-review check when an in-scope PR reports success without execution
# evidence (#2337).
#
# The ci-workflows reusable deliberately reports GREEN on some infra-failure
# classes; this script is a repo-owned supplement that catches the subset the
# issue filed: an in-scope PR whose security-review job succeeded suspiciously
# fast, or whose logs show a validation skip while the check still went green.
#
# Intended to run as a sibling job after security-review in
# .github/workflows/claude-security-review.yml.
#
# Environment:
#   GITHUB_RUN_ID          current workflow run (required)
#   GITHUB_REPOSITORY      owner/repo (required)
#   GITHUB_EVENT_NAME      pull_request expected
#   GITHUB_BASE_REF        base branch name
#   GITHUB_HEAD_REF        head branch name (optional)
#   GITHUB_ACTOR           PR author login
#   MIN_REVIEW_SECONDS     minimum plausible duration (default 45)
#   SKIP_ACTORS            comma-separated actors exempt from review
#
# Exit: 0 evidence OK or not applicable; 1 in-scope false pass detected.

set -euo pipefail

MIN_REVIEW_SECONDS="${MIN_REVIEW_SECONDS:-45}"
SKIP_ACTORS="${SKIP_ACTORS:-dependabot[bot],claude[bot],melodic-ai[bot],melodic-standards-sync[bot]}"
PATHS_FILE="${PATHS_FILE:-.github/claude-security-paths}"

usage() {
  cat <<'EOF'
verify-security-review-evidence.sh — guard against in-scope security-review false passes.

Reads the current workflow run's security-review job. Exits 0 when the PR is
out of scope, exempt, skipped, or shows plausible execution evidence. Exits 1
when an in-scope PR's security-review job succeeded too quickly or its logs
show a validation skip (#2337).
EOF
}

pr_touches_security_paths() {
  local base_ref="$1"
  [[ -f "$PATHS_FILE" ]] || return 0
  python3 - "$PATHS_FILE" "$base_ref" <<'PY'
import fnmatch
import re
import subprocess
import sys

paths_file, base_ref = sys.argv[1], sys.argv[2]
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

diff = subprocess.run(
    ["git", "diff", "--name-only", f"origin/{base_ref}...HEAD"],
    check=False,
    capture_output=True,
    text=True,
)
changed = [line for line in diff.stdout.splitlines() if line]
for path in changed:
    for pat in patterns:
        if pattern_matches(path, pat):
            sys.exit(0)
sys.exit(1)
PY
}

job_duration_seconds() {
  local started completed
  started="$1"
  completed="$2"
  local s c
  s=$(date -u -d "$started" +%s) # portability-ok: GNU date -d for GitHub Actions ISO timestamps; CI runs on ubuntu only
  c=$(date -u -d "$completed" +%s) # portability-ok: GNU date -d for GitHub Actions ISO timestamps; CI runs on ubuntu only
  echo $((c - s))
}

main() {
  case "${1:-}" in
    -h | --help) usage; exit 0 ;;
    *) ;;
  esac

  [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]] || {
    echo "not a pull_request event — guard not applicable"
    exit 0
  }
  [[ -n "${GITHUB_RUN_ID:-}" && -n "${GITHUB_REPOSITORY:-}" ]] || {
    echo "ERROR: GITHUB_RUN_ID and GITHUB_REPOSITORY are required" >&2
    exit 1
  }
  command -v gh >/dev/null 2>&1 || {
    echo "ERROR: gh required" >&2
    exit 1
  }
  command -v jq >/dev/null 2>&1 || {
    echo "ERROR: jq required" >&2
    exit 1
  }

  if [[ ",${SKIP_ACTORS}," == *",${GITHUB_ACTOR:-},"* ]]; then
    echo "actor ${GITHUB_ACTOR} is skip-listed — guard not applicable"
    exit 0
  fi

  local base_ref="${GITHUB_BASE_REF:-main}"
  git fetch origin "$base_ref" --depth=1 >/dev/null 2>&1 || true
  pr_touches_security_paths "$base_ref"
  local in_scope=$?
  if (( in_scope != 0 )); then
    echo "diff does not touch security-relevant paths — guard not applicable"
    exit 0
  fi

  local jobs_json
  jobs_json="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs" --paginate)"
  local job
  job="$(printf '%s' "$jobs_json" | jq -c '.jobs[] | select(.name == "security-review")' | head -n1)"
  if [[ -z "$job" ]]; then
    echo "ERROR: security-review job not found in run $GITHUB_RUN_ID" >&2
    exit 1
  fi

  local conclusion started completed
  conclusion="$(printf '%s' "$job" | jq -r '.conclusion // .status')"
  started="$(printf '%s' "$job" | jq -r '.started_at // empty')"
  completed="$(printf '%s' "$job" | jq -r '.completed_at // empty')"

  if [[ "$conclusion" == "skipped" ]]; then
    echo "security-review job skipped — guard not applicable"
    exit 0
  fi
  if [[ "$conclusion" != "success" ]]; then
    echo "security-review job conclusion=$conclusion — deferring to job status"
    exit 0
  fi

  local duration=0
  if [[ -n "$started" && -n "$completed" ]]; then
    duration="$(job_duration_seconds "$started" "$completed")"
  fi

  local log_file
  log_file="$(mktemp)"
  trap 'rm -f "$log_file"' RETURN
  gh run view "$GITHUB_RUN_ID" --repo "$GITHUB_REPOSITORY" --job "$(printf '%s' "$job" | jq -r '.id')" --log >"$log_file" 2>/dev/null || true

  if grep -qE 'workflow-validation skip|class=skipped-validation|review-ran.*false' "$log_file" 2>/dev/null; then
    echo "ERROR: security-review reported success but logs show a validation skip or review-ran=false (#2337)" >&2
    exit 1
  fi

  if (( duration > 0 && duration < MIN_REVIEW_SECONDS )); then
    echo "ERROR: in-scope security-review succeeded in ${duration}s (<${MIN_REVIEW_SECONDS}s) — likely no review ran (#2337)" >&2
    exit 1
  fi

  echo "security-review evidence OK (duration=${duration}s, in-scope)"
}

main "$@"
