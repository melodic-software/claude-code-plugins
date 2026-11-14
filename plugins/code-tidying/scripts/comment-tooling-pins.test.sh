#!/usr/bin/env bash
# Contract: the eval seed (comment-tooling-seed.sh) installs exactly the pygments
# and tree-sitter* requirements of .github/requirements-ci.txt, version and hash
# set, read from that file at seed time. A pin changed in that file alone moves
# the seed with it, with no second pin file to move.
# Usage: comment-tooling-pins.test.sh [<ci requirements>]
# test-scope: plugins/code-tidying/evals/fixtures/comment-tooling-seed.sh .github/requirements-ci.txt
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
seed="$root/plugins/code-tidying/evals/fixtures/comment-tooling-seed.sh"
ci_req="${1:-$root/.github/requirements-ci.txt}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

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

rc=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  rc=1
}

# The seed's requirements for CI file $1 are that file's pygments and tree-sitter*
# requirements, and cover every package the seed imports.
check() {
  local ci="$1" all want got name
  all="$(requirements "$ci")"
  want="$(grep -E '^(pygments|tree-sitter(-[a-z0-9_-]+)?)==' <<<"$all" || true)"
  bash "$seed" --print-requirements "$ci" >"$scratch/seed.txt"
  got="$(requirements "$scratch/seed.txt")"
  [[ "$got" == "$want" ]] || fail "the seed's requirements differ from the pygments and tree-sitter pins of $ci"
  for name in pygments tree-sitter tree-sitter-bash tree-sitter-python; do
    grep -qE "^${name}==[^ ]+ --hash=" <<<"$got" || fail "the seed installs no hash-pinned $name from $ci"
  done
  if grep -qvE '^(pygments|tree-sitter(-[a-z0-9_-]+)?)==' <<<"$got"; then
    fail "the seed installs a package other than pygments and tree-sitter* from $ci"
  fi
}

check "$ci_req"

# With no file named, the seed reads the repository's .github/requirements-ci.txt.
if [[ -z "${1:-}" ]]; then
  bash "$seed" --print-requirements >"$scratch/default.txt"
  bash "$seed" --print-requirements "$ci_req" >"$scratch/named.txt"
  cmp -s "$scratch/default.txt" "$scratch/named.txt" ||
    fail "the seed's default requirements are not those of $ci_req"
fi

# A tree-sitter bump in the CI file alone: new version, one hash replaced.
moved="$scratch/requirements-ci.txt"
new_hash="sha256:$(printf 'f%.0s' {1..64})"
awk -v h="$new_hash" '
  /^tree-sitter==/ { sub(/==[^ ]+/, "==99.0.0"); bump = 1 }
  bump && /--hash=/ { sub(/sha256:[0-9a-f]+/, h); bump = 0 }
  { print }
' "$ci_req" >"$moved"
check "$moved"
grep -qF -- "--hash=$new_hash" <(bash "$seed" --print-requirements "$moved") ||
  fail "a tree-sitter bump in the CI file alone does not reach the seed"

[[ "$rc" -eq 0 ]] && printf 'ok: the eval seed installs the pygments and tree-sitter pins of %s, and a bump there alone reaches it\n' "$ci_req"
exit "$rc"
