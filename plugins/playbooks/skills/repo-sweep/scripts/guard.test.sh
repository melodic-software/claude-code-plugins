#!/usr/bin/env bash
# Tests for guard.sh: a stub gh on PATH serves the current PR list, a fixture repo in a
# temp dir plays the sweep branch.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
"pr list --author @me --limit 1000 --json number") cat "$GH_NOW" ;;
*) printf 'gh stub: unexpected: %s\n' "$*" >&2; exit 64 ;;
esac
EOF
chmod +x "$TMP/bin/gh"

gitf() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
repo="$TMP/repo"
mkdir -p "$repo"
gitf -C "$repo" init --quiet
gitf -C "$repo" checkout --quiet -b chore/repo-sweep-fixture-20260926
commit() { gitf -C "$repo" commit --quiet --no-verify --allow-empty -m "$1"; }
commit 'repo-sweep: seed'
base=$(git -C "$repo" rev-parse HEAD)
printf '[{"number":1},{"number":3}]\n' >"$TMP/snap.json"
cp "$TMP/snap.json" "$TMP/now.json"

run() { # sets out, rc
  out=$(cd "$repo" && PATH="$TMP/bin:$PATH" GH_NOW="$TMP/now.json" GIT_CEILING_DIRECTORIES="$TMP" \
    bash "$SCRIPT" "$@" 2>"$TMP/err")
  rc=$?
}

run "$base" "$TMP/snap.json"
assert_eq "no change: exit 0, no output" "0 " "$rc $out"

commit 'skill commit 1'
run "$base" "$TMP/snap.json"
assert_eq "one skill commit: squash (exit 11)" "11 squash git reset --soft $base" "$rc $out"
commit 'skill commit 2'
run "$base" "$TMP/snap.json"
assert_eq "two skill commits: squash (exit 11)" "11 squash git reset --soft $base" "$rc $out"

printf '[{"number":3},{"number":1},{"number":4}]\n' >"$TMP/now.json"
run "$base" "$TMP/snap.json"
assert_eq "new PR: stop (exit 10) beats squash" "10 new-pr 4" "$rc $out"
cp "$TMP/snap.json" "$TMP/now.json"

gitf -C "$repo" checkout --quiet -b skill-branch
run "$base" "$TMP/snap.json"
assert_eq "branch change: stop" "10 branch-changed skill-branch" "$rc $out"
gitf -C "$repo" checkout --quiet --detach
run "$base" "$TMP/snap.json"
assert_eq "detached HEAD: stop" "10 branch-changed detached" "$rc $out"
gitf -C "$repo" checkout --quiet chore/repo-sweep-fixture-20260926

gitf -C "$repo" reset --quiet --hard "$base"
gitf -C "$repo" commit --quiet --no-verify --amend --allow-empty -m 'rewritten seed'
printf '[{"number":1},{"number":3},{"number":5}]\n' >"$TMP/now.json"
run "$base" "$TMP/snap.json"
assert_eq "history rewritten and a new PR: both reported" "10 base-not-ancestor $base
new-pr 5" "$rc $out"

rm "$TMP/now.json"
run "$base" "$TMP/snap.json"
assert_eq "gh failing: exit 1" "1" "$rc"
run nosuchrev "$TMP/snap.json"
assert_eq "unknown base: exit 1" "1" "$rc"
run "$base"
assert_eq "no snapshot argument: exit 2" "2" "$rc"

if ((FAILED)); then
  printf '%d FAILED\n' "$FAILED" >&2
  exit 1
fi
printf 'guard.test.sh: all passed\n'
