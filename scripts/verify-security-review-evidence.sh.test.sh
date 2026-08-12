#!/usr/bin/env bash
# Self-tests for verify-security-review-evidence.sh path matching helper.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATHS_FILE="$SCRIPT_DIR/../.github/claude-security-paths"

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

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
exit 1
