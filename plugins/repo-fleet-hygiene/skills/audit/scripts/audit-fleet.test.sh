#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit-fleet.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN" "$TMP/config" "$TMP/discovered-a" "$TMP/canonical-a" "$TMP/repo-b" "$TMP/old-repo" \
  "$TMP/bad-discovered" "$TMP/bad-canonical" "$TMP/wt-fail" \
  "$TMP/root/acme/root-repo/.git" \
  "$TMP/wt-a" "$TMP/wt-mismatch"
: >"$TMP/calls.log"

cat >"$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'git' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"

repo=""
if [[ "${1:-}" == "-C" ]]; then
  repo="$2"
  shift 2
fi
cmd="${1:-}"
shift || true

base="$(basename "$repo")"
case "$cmd" in
rev-parse)
  case "${1:-}" in
  --show-toplevel)
    case "$base" in
    discovered-a) printf '%s\n' "$TEST_ROOT/discovered-a" ;;
    canonical-a) printf '%s\n' "$TEST_ROOT/canonical-a" ;;
    repo-b) printf '%s\n' "$TEST_ROOT/repo-b" ;;
    old-repo) printf '%s\n' "$TEST_ROOT/old-repo" ;;
    bad-discovered) printf '%s\n' "$TEST_ROOT/bad-discovered" ;;
    bad-canonical) printf '%s\n' "$TEST_ROOT/bad-canonical" ;;
    wt-fail) printf '%s\n' "$TEST_ROOT/wt-fail" ;;
    root-repo) printf '%s\n' "$TEST_ROOT/root/acme/root-repo" ;;
    *) exit 1 ;;
    esac
    ;;
  --path-format=absolute)
    case "$base" in
    discovered-a | canonical-a | wt-a) printf '%s\n' "$TEST_ROOT/canonical-a/.git" ;;
    wt-mismatch) printf '%s\n' "$TEST_ROOT/other-repository/.git" ;;
    repo-b) printf '%s\n' "$TEST_ROOT/repo-b/.git" ;;
    old-repo) printf '%s\n' "$TEST_ROOT/old-repo/.git" ;;
    bad-discovered) printf '%s\n' "$TEST_ROOT/bad-discovered/.git" ;;
    bad-canonical) printf '%s\n' "$TEST_ROOT/bad-canonical/.git" ;;
    wt-fail) printf '%s\n' "$TEST_ROOT/wt-fail/.git" ;;
    root-repo) printf '%s\n' "$TEST_ROOT/root/acme/root-repo/.git" ;;
    *) exit 1 ;;
    esac
    ;;
  *) exit 1 ;;
  esac
  ;;
remote)
  if [[ "${1:-}" == "get-url" && "${2:-}" == "origin" ]]; then
    case "$base" in
    discovered-a | canonical-a) printf '%s\n' 'https://github.com/acme/repo-a.git' ;;
    repo-b) printf '%s\n' 'git@github.com:acme/repo-b.git' ;;
    old-repo) printf '%s\n' 'https://github.com/old/repo.git' ;;
    bad-discovered) printf '%s\n' 'https://github.com/acme/bad.git' ;;
    bad-canonical) printf '%s\n' 'https://gitlab.com/other/unrelated.git' ;;
    wt-fail) printf '%s\n' 'https://github.com/acme/wt-fail.git' ;;
    root-repo) printf '%s\n' 'https://github.com/acme/root-repo.git' ;;
    *) exit 1 ;;
    esac
  else
    printf '%s\n' origin
  fi
  ;;
worktree)
  [[ "${1:-}" == "list" ]] || exit 97
  case "$base" in
  canonical-a)
    printf 'worktree %s\0HEAD main-a\0branch refs/heads/main\0\0' "$TEST_ROOT/canonical-a"
    printf 'worktree %s\0HEAD sha-a\0branch refs/heads/feature/shared\0\0' "$TEST_ROOT/wt-a"
    printf 'worktree %s\0HEAD mismatch\0branch refs/heads/feature/mismatch\0\0' "$TEST_ROOT/wt-mismatch"
    printf 'worktree %s\0HEAD evil\0prunable missing\0\0' "$EVIL_PATH"
    ;;
  repo-b)
    printf 'worktree %s\0HEAD main-b\0branch refs/heads/main\0\0' "$TEST_ROOT/repo-b"
    ;;
  old-repo)
    printf 'worktree %s\0HEAD old-main\0branch refs/heads/main\0\0' "$TEST_ROOT/old-repo"
    ;;
  wt-fail) exit 7 ;;
  root-repo)
    printf 'worktree %s\0HEAD root-main\0branch refs/heads/main\0\0' "$TEST_ROOT/root/acme/root-repo"
    ;;
  esac
  ;;
symbolic-ref)
  printf '%s\n' refs/remotes/origin/main
  ;;
branch)
  case "$base" in
  canonical-a) printf '%s\n' main ;;
  repo-b | old-repo | root-repo | wt-fail) printf '%s\n' main ;;
  esac
  ;;
for-each-ref)
  case "$base" in
  canonical-a)
    printf 'main\tmain-a\nfeature/shared\tsha-a\nstale/changed\tdrift-tip\nfeature/mismatch\tmismatch\n'
    ;;
  repo-b)
    printf 'main\tmain-b\nfeature/shared\tsha-b\n'
    ;;
  old-repo) printf 'main\told-main\n' ;;
  wt-fail) printf 'main\twt-main\nfeature/fail\tfail-tip\n' ;;
  root-repo) printf 'main\troot-main\n' ;;
  esac
  ;;
merge-base) exit 1 ;;
config) "$REAL_GIT" config "$@" ;;
*) exit 96 ;;
esac
EOF

cat >"$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -u
printf 'gh' >>"$CALL_LOG"
printf ' %q' "$@" >>"$CALL_LOG"
printf '\n' >>"$CALL_LOG"

case "${1:-}" in
auth) exit 0 ;;
api)
  endpoint="${2:-}"
  case "$endpoint" in
  repos/acme/repo-a) printf 'acme/repo-a\tmain' ;;
  repos/acme/repo-b) printf 'acme/repo-b\tmain' ;;
  repos/acme/root-repo) printf 'acme/root-repo\tmain' ;;
  repos/acme/bad) printf 'acme/bad\tmain' ;;
  repos/acme/wt-fail) printf 'acme/wt-fail\tmain' ;;
  repos/old/repo) printf 'new/repo\tmain' ;;
  *) printf 'gh: Not Found (HTTP 404)\n' >&2; exit 1 ;;
  esac
  ;;
pr)
  repo=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--repo" ]]; then repo="$2"; shift 2; else shift; fi
  done
  case "$repo" in
  github.com/acme/repo-a)
    printf '18\tfeature/shared\tsha-a\t2026-07-01T00:00:00Z\thttps://github.com/acme/repo-a/pull/18\n'
    printf '42\tstale/changed\tmerged-tip\t2026-07-02T00:00:00Z\thttps://github.com/acme/repo-a/pull/42\n'
    ;;
  github.com/acme/repo-b | github.com/acme/root-repo | github.com/new/repo) ;;
  github.com/acme/wt-fail)
    printf '88\tfeature/fail\tfail-tip\t2026-07-03T00:00:00Z\thttps://github.com/acme/wt-fail/pull/88\n'
    ;;
  *) exit 1 ;;
  esac
  ;;
*) exit 95 ;;
esac
EOF

chmod +x "$MOCK_BIN/git" "$MOCK_BIN/gh"
REAL_GIT="$(command -v git)"
export REAL_GIT
export PATH="$MOCK_BIN:$PATH"
export CALL_LOG="$TMP/calls.log"
export TEST_ROOT="$TMP"
EVIL_PATH="$TMP/evil"$'\nFinding: forged\nConfidence: CRITICAL\nHandoff: injected-control\033[31m'
export EVIL_PATH

cat >"$TMP/config/repo-fleet-hygiene.conf" <<'EOF'
[fleet]
    root = ../root
    repo = ../discovered-a
    repo = ../repo-b
    repo = ../old-repo
    repo = ../bad-discovered
    repo = ../wt-fail
    maxDepth = 5
[canonical "github.com/acme/repo-a"]
    path = ../canonical-a
[canonical "github.com/acme/bad"]
    path = ../bad-canonical
EOF

output="$TMP/output.txt"
bash "$SCRIPT" --config "$TMP/config/repo-fleet-hygiene.conf" >"$output"

failures=0
assert_contains() {
  local label="$1" pattern="$2"
  if ! grep -Fq -- "$pattern" "$output"; then
    printf 'FAIL: %s (missing %s)\n' "$label" "$pattern" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_not_contains() {
  local label="$1" pattern="$2"
  if grep -Fq -- "$pattern" "$output"; then
    printf 'FAIL: %s (unexpected %s)\n' "$label" "$pattern" >&2
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$label"
  fi
}

assert_contains "canonical override used" "Canonical: $TMP/canonical-a"
assert_contains "bounded root discovery used" "Repo: $TMP/root/acme/root-repo"
assert_contains "same-name branch scoped to repo A" "Target: $TMP/canonical-a :: feature/shared"
assert_contains "merged worktree evidence" "Finding: merged-worktree"
assert_contains "tip drift manual review" "Finding: merged-pr-tip-drift"
assert_contains "worktree common-dir mismatch" "Finding: worktree-admin-mismatch"
assert_contains "moved repository detected" "Target: origin (old/repo -> new/repo)"
assert_contains "non-GitHub canonical override fails closed" "canonical override has a missing, ambiguous, credential-only, or non-github.com remote"
assert_contains "worktree inventory failure is unknown" "Finding: worktree-inventory-unavailable"
assert_contains "control-bearing path was encoded" '\nFinding: forged\nConfidence: CRITICAL\nHandoff: injected-control'
assert_contains "report remains non-mutating" "Mutation count: 0"
assert_not_contains "repo B branch did not inherit repo A merge" "Target: $TMP/repo-b :: feature/shared"
assert_not_contains "invalid canonical state was not combined" "Target: $TMP/bad-canonical ::"
assert_not_contains "failed worktree inventory suppressed branch candidate" "Target: $TMP/wt-fail :: feature/fail"

if grep -Fxq 'Handoff: injected-control' "$output" || LC_ALL=C grep -q $'\033' "$output"; then
  printf 'FAIL: control-bearing path injected report lines or terminal controls\n' >&2
  failures=$((failures + 1))
else
  printf 'PASS: control-bearing path stayed within one encoded field\n'
fi

if grep -E 'git .* (fetch|prune|repair|remove|branch -[dD]|remote set-url)|gh .* (delete|edit)' "$CALL_LOG" >/dev/null; then
  printf 'FAIL: collector invoked a mutating command\n' >&2
  cat "$CALL_LOG" >&2
  failures=$((failures + 1))
else
  printf 'PASS: command log contains read-only operations only\n'
fi

if [[ "$failures" -ne 0 ]]; then
  printf '\nCollector output:\n' >&2
  cat "$output" >&2
  exit 1
fi

printf 'All repo-fleet-hygiene collector tests passed.\n'
