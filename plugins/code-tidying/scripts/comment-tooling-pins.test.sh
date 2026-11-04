#!/usr/bin/env bash
# Contract: every requirement in the eval seed's comment-tooling.requirements.txt
# matches the same package's requirement in .github/requirements-ci.txt, version
# and hash set, so a pin bumped on the reviewed surface cannot leave the eval
# seed installing the old one.
# Usage: comment-tooling-pins.test.sh [<eval requirements> <ci requirements>]
# test-scope: plugins/code-tidying/evals/fixtures/comment-tooling.requirements.txt .github/requirements-ci.txt
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
eval_req="${1:-$root/plugins/code-tidying/evals/fixtures/comment-tooling.requirements.txt}"
ci_req="${2:-$root/.github/requirements-ci.txt}"

# One line per requirement: continuations joined, comments dropped, hashes sorted.
requirements() {
  awk '
    /^[[:space:]]*#/ { next }
    { sub(/[[:space:]]*\\$/, ""); gsub(/^[[:space:]]+/, ""); if ($0 == "") next }
    /^--hash=/ { req = req " " $0; next }
    { if (req != "") print req; req = $0 }
    END { if (req != "") print req }
  ' "$1" | while read -r spec hashes; do
    printf '%s %s\n' "$spec" "$(tr ' ' '\n' <<<"$hashes" | sort | paste -sd ' ')"
  done
}

ci="$(requirements "$ci_req")"
rc=0
count=0
while read -r spec rest; do
  count=$((count + 1))
  name="${spec%%==*}"
  match="$(grep -E "^${name//./\\.}==" <<<"$ci" || true)"
  if [[ -z "$match" ]]; then
    printf 'FAIL: %s is not pinned in %s\n' "$name" "$ci_req" >&2
    rc=1
  elif [[ "$match" != "$spec $rest" ]]; then
    printf 'FAIL: %s differs from %s (version or hashes)\n' "$name" "$ci_req" >&2
    rc=1
  fi
done < <(requirements "$eval_req")
if [[ "$count" -eq 0 ]]; then
  printf 'FAIL: no requirement read from %s\n' "$eval_req" >&2
  rc=1
fi
[[ "$rc" -eq 0 ]] && printf 'ok: %d comment-tooling pins match %s\n' "$count" "$ci_req"
exit "$rc"
