#!/usr/bin/env bash
# Tests for github_remote_path and github_repo_name: which remote URLs name a
# github.com repository, and which segment is the repository.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=github-remote.sh
source "$SCRIPT_DIR/github-remote.sh"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# expect_path URL PATH: PATH is what github_remote_path prints; "-" means the
# URL fails and prints nothing.
expect_path() {
  local url="$1" want="$2" got rc=0
  got="$(github_remote_path "$url")" || rc=$?
  if [[ "$want" == "-" ]]; then
    if [[ $rc -ne 0 && -z "$got" ]]; then pass "path fails: $url"; else fail "path should fail: $url (got '$got')"; fi
  elif [[ $rc -eq 0 && "$got" == "$want" ]]; then
    pass "path: $url"
  else
    fail "path: $url wanted '$want' got '$got' (rc $rc)"
  fi
}

# expect_name URL REPO: same for github_repo_name.
expect_name() {
  local url="$1" want="$2" got rc=0
  got="$(github_repo_name "$url")" || rc=$?
  if [[ "$want" == "-" ]]; then
    if [[ $rc -ne 0 && -z "$got" ]]; then pass "name fails: $url"; else fail "name should fail: $url (got '$got')"; fi
  elif [[ $rc -eq 0 && "$got" == "$want" ]]; then
    pass "name: $url"
  else
    fail "name: $url wanted '$want' got '$got' (rc $rc)"
  fi
}

for url in \
  "https://github.com/owner/repo.git" \
  "https://github.com/owner/repo" \
  "https://github.com/owner/repo/" \
  "git@github.com:owner/repo.git" \
  "ssh://git@github.com/owner/repo.git" \
  "https://user:token@github.com/owner/repo.git" \
  "https://GitHub.COM/owner/repo.git" \
  "https://www.github.com/owner/repo.git" \
  "https://github.com:443/owner/repo.git" \
  "https://github.com:/owner/repo.git" \
  "ssh://git@github.com:22/owner/repo.git" \
  "https://github.com//owner/repo.git" \
  "git@github.com:/owner/repo.git"; do
  expect_path "$url" "owner/repo"
  expect_name "$url" "repo"
done

# The path keeps its extra segments; the name stops at the second.
expect_path "https://github.com/owner/repo/tree/main" "owner/repo/tree/main"
expect_name "https://github.com/owner/repo/tree/main" "repo"

# One segment is an owner, not a repository.
expect_path "https://github.com/owner" "owner"
expect_name "https://github.com/owner" "-"
expect_name "https://github.com/owner/" "-"

# rest='/owner/repo' names repo, not owner.
expect_name "https://github.com///owner/repo" "repo"

for url in \
  "" \
  "unknown" \
  "https://evilgithub.com/owner/repo.git" \
  "https://github.com.evil.example/owner/repo.git" \
  "https://api.github.com/owner/repo.git" \
  "https://gitlab.example/acme/repo.git" \
  "https://evil.example/github.com/owner/repo.git" \
  "git@evil.example:github.com/owner/repo.git" \
  "https://github.com:evil/owner/repo.git" \
  "https://github.com:8a/owner/repo.git" \
  "file:///srv/git/github.com/owner/repo.git" \
  "file://github.com/owner/repo.git" \
  "/srv/git/github.com/owner/repo.git" \
  "../github.com/owner/repo" \
  "github.com/owner/repo" \
  "github.com"; do
  expect_path "$url" "-"
  expect_name "$url" "-"
done

# The function leaves the caller's nocasematch setting as it found it.
shopt -u nocasematch
github_remote_path "https://GITHUB.com/o/r" >/dev/null
if shopt -q nocasematch; then fail "nocasematch left on"; else pass "nocasematch restored off"; fi
shopt -s nocasematch
github_remote_path "https://GITHUB.com/o/r" >/dev/null
if shopt -q nocasematch; then pass "nocasematch restored on"; else fail "nocasematch left off"; fi
shopt -u nocasematch

printf '\n%d passed, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
