#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/collision-hotspots.sh"

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

for tool in git jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP: $tool not installed" >&2
    exit 0
  fi
done

GIT_BIN="$(command -v git)"
JQ_BIN="$(command -v jq)"

g() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }

BUILD="$TEST_TMPDIR/build"
REMOTE="$TEST_TMPDIR/remote.git"
g init -q "$BUILD"
g init -q --bare "$REMOTE"
printf '%s\n' a b c d e f g h i j >"$BUILD/shared.txt"
printf '%s\n' base >"$BUILD/CHANGELOG.md"
# shellcheck disable=SC2016 # literal names, never expanded
HOSTILE=('x$(touch pwned-dollar)' 'y`touch pwned-tick`' 'a[1]' 'b[$(touch pwned-sub)]')
for h in "${HOSTILE[@]}"; do printf '%s\n' a b c d e f g h i j >"$BUILD/$h"; done
g -C "$BUILD" add .
g -C "$BUILD" commit -qm base
g -C "$BUILD" push -q "$REMOTE" main

pr() {
  g -C "$BUILD" checkout -q -b "pr$1" main
  sed -i.bak "$2" "$BUILD/shared.txt"
  rm -f "$BUILD/shared.txt.bak"
  if [[ -n "${3:-}" ]]; then printf '%s\n' "$3" >>"$BUILD/CHANGELOG.md"; fi
  g -C "$BUILD" commit -qam "pr $1"
  g -C "$BUILD" push -q "$REMOTE" "pr$1:refs/pull/$1/head"
}
pr 1 '1s/a/one/' 'entry one'
pr 2 '1s/a/uno/' 'entry two'
pr 3 '10s/j/ten/'
pr 4 '1s/a/eins/'
PR1_SHA="$(git -C "$BUILD" rev-parse pr1)"

hpr() {
  local h line
  g -C "$BUILD" checkout -q -b "pr$1" main
  for h in "${HOSTILE[@]}"; do
    line="$2"
    [[ "$h" == 'a[1]' ]] && line="$3"
    sed -i.bak "${line}s/.*/pr$1/" "$BUILD/$h"
    rm -f "$BUILD/$h.bak"
  done
  g -C "$BUILD" commit -qam "pr $1"
  g -C "$BUILD" push -q "$REMOTE" "pr$1:refs/pull/$1/head"
}
hpr 11 1 1
hpr 12 5 1
hpr 13 10 10
HOSTILE_LISTING="$TEST_TMPDIR/hostile.json"
# shellcheck disable=SC2016 # a jq program, not a shell expansion
"$JQ_BIN" -n --args '[11, 12, 13] | map({number: ., createdAt: "2026-09-01T00:00:00Z",
  closedAt: null, files: ($ARGS.positional | map({path: .}))})' "${HOSTILE[@]}" >"$HOSTILE_LISTING"

FILES100="$("$JQ_BIN" -nc '[range(1; 101) | {path: "bulk/f\(.).txt", additions: 1, deletions: 0}]')"
LISTING="$TEST_TMPDIR/prs.json"
# shellcheck disable=SC2016 # a jq program, not a shell expansion
"$JQ_BIN" -n --argjson bulk "$FILES100" '[
  {number: 1, createdAt: "2026-09-01T00:00:00Z", closedAt: null,
   files: [{path: "shared.txt"}, {path: "CHANGELOG.md"}]},
  {number: 2, createdAt: "2026-09-01T01:00:00Z", closedAt: null,
   files: [{path: "shared.txt"}, {path: "CHANGELOG.md"}]},
  {number: 3, createdAt: "2026-09-01T02:00:00Z", closedAt: null,
   files: [{path: "shared.txt"}]},
  {number: 4, createdAt: "2026-08-01T00:00:00Z", closedAt: "2026-08-02T00:00:00Z",
   files: [{path: "shared.txt"}]},
  {number: 6, createdAt: "2026-07-01T00:00:00Z", closedAt: "2026-07-02T00:00:00Z",
   files: $bulk}
]' >"$LISTING"

TAB_LISTING="$TEST_TMPDIR/tab.json"
"$JQ_BIN" -n '[{number: 9, createdAt: "2026-09-01T00:00:00Z", closedAt: null,
  files: [{path: "bad\tname.txt"}]}]' >"$TAB_LISTING"

BIN="$TEST_TMPDIR/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_GH_LOG"
case "$1 $2" in
"pr list")
  if [[ -n "${STUB_GH_FAIL:-}" ]]; then exit 1; fi
  cat "$STUB_GH_JSON"
  ;;
"repo view") printf '{"nameWithOwner":"%s","url":"%s","sshUrl":"%s"}\n' "${STUB_GH_NWO:-octo/demo}" "$STUB_GH_URL" "${STUB_GH_SSH:-}" ;; # spellchecker:disable-line
*) exit 1 ;;
esac
EOF
chmod +x "$BIN/gh"

FAILBIN="$TEST_TMPDIR/failbin"
mkdir -p "$FAILBIN"
cp "$BIN/gh" "$FAILBIN/gh"
cat >"$FAILBIN/git" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == merge-tree && "\$*" == *refs/collision-hotspots/* ]]; then exit 128; fi
exec "$GIT_BIN" "\$@"
EOF
chmod +x "$FAILBIN/git"

NOGH="$TEST_TMPDIR/nogh"
mkdir -p "$NOGH"
ln -s "$GIT_BIN" "$NOGH/git"
ln -s "$JQ_BIN" "$NOGH/jq"

export STUB_GH_LOG="$TEST_TMPDIR/gh.log"
export STUB_GH_URL="$REMOTE"

fresh_clone() {
  local dir
  dir="$(mktemp -d "$TEST_TMPDIR/work.XXXXXX")/repo"
  git clone -q --no-local "$REMOTE" "$dir"
  printf '%s' "$dir"
}
run() {
  local dir="$1" listing="$2"
  shift 2
  OUT="$(cd "$dir" && STUB_GH_JSON="$listing" PATH="$BIN:$PATH" bash "$SCRIPT" "$@" 2>&1)"
  RC=$?
}
ref_count() { git -C "$1" for-each-ref refs/collision-hotspots | grep -c . || true; }
has_row() { grep -qxF "$2" <<<"$1" && echo yes || echo no; }

W="$(fresh_clone)"
run "$W" "$LISTING" --prs 50
assert_exit "full run exits 0" 0 "$RC"
assert_eq "conflicting pair counts one conflict over three overlapping pairs" yes "$(has_row "$OUT" "$(printf '1\t3\tshared.txt')")"
assert_contains "three overlapping pairs; the closed-before PR is not paired" "$OUT" "pairs: 3 overlapping pairs share a ranked file; replaying 3 (--max-pairs 200), skipped 0"
assert_contains "100-file PR prints a gap line" "$OUT" "gap: PR #6 lists 100 files"
assert_not_contains "a PR under the limit prints no gap line" "$OUT" "gap: PR #1 "
assert_contains "changelog named on the bump line" "$OUT" "known bump hotspots"
assert_contains "bump line names the changelog with its PR count" "$OUT" "CHANGELOG.md (2 PRs)"
assert_not_contains "changelog is not ranked" "$OUT" $'\tCHANGELOG.md'
assert_eq "run namespace is gone after exit" 0 "$(ref_count "$W")"
assert_contains "gh read every PR state" "$(cat "$STUB_GH_LOG")" "pr list --state all --limit 50"

W="$(fresh_clone)"
run "$W" "$LISTING" --prs 50 --max-pairs 1
assert_exit "--max-pairs 1 exits 0" 0 "$RC"
assert_contains "--max-pairs 1 replays one and prints the skipped count" "$OUT" "replaying 1 (--max-pairs 1), skipped 2"
assert_contains "one replayed pair ranks no file" "$OUT" "ranked: none"

W="$(fresh_clone)"
run "$W" "$LISTING" --prs 50 --dry-run
assert_exit "--dry-run exits 0" 0 "$RC"
assert_contains "--dry-run lists a pair it would replay" "$OUT" "would replay: #1 #2"
assert_eq "--dry-run creates no ref" 0 "$(ref_count "$W")"
if git -C "$W" cat-file -e "$PR1_SHA^{commit}" 2>/dev/null; then fetched=yes; else fetched=no; fi
assert_eq "--dry-run fetches nothing" no "$fetched"

W="$(fresh_clone)"
run "$W" "$LISTING" --prs 50 --exclude 'shared.*'
assert_exit "--exclude exits 0" 0 "$RC"
assert_contains "--exclude moves the file to the bump line" "$OUT" "shared.txt (4 PRs)"
assert_contains "--exclude leaves no pair" "$OUT" "pairs: 0 overlapping pairs"

W="$(fresh_clone)"
: >"$STUB_GH_LOG"
run "$W" "$LISTING" --prs 50 --repo octo/demo
assert_exit "--repo exits 0" 0 "$RC"
assert_eq "--repo ranks the same file" yes "$(has_row "$OUT" "$(printf '1\t3\tshared.txt')")"
assert_contains "--repo is passed to gh" "$(cat "$STUB_GH_LOG")" "--repo octo/demo"

FORK="$TEST_TMPDIR/fork.git"
g init -q --bare "$FORK"
g -C "$BUILD" push -q "$FORK" main
W="$(fresh_clone)"
git -C "$W" remote set-url origin "$FORK"
: >"$STUB_GH_LOG"
# spellchecker:ignore-next-line
OUT="$(cd "$W" && STUB_GH_NWO=up/stream STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
RC=$?
assert_exit "a fork clone exits 0" 0 "$RC"
assert_not_contains "a fork clone fetches every head from gh's repository" "$OUT" "could not be fetched"
assert_eq "a fork clone ranks from gh's repository" yes "$(has_row "$OUT" "$(printf '1\t3\tshared.txt')")"
assert_contains "a fork clone lists from the resolved repository" "$(cat "$STUB_GH_LOG")" "--repo up/stream"

NOWHERE="$TEST_TMPDIR/nowhere.git"
W="$(fresh_clone)"
git -C "$W" remote set-url origin https://github.com/Octo/Demo.git
git -C "$W" config url."$REMOTE".insteadOf https://github.com/Octo/Demo.git
OUT="$(cd "$W" && STUB_GH_URL="$NOWHERE" STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
RC=$?
assert_exit "origin naming gh's repository exits 0" 0 "$RC"
assert_not_contains "origin naming gh's repository fetches every head from origin" "$OUT" "could not be fetched"
assert_eq "origin naming gh's repository ranks" yes "$(has_row "$OUT" "$(printf '1\t3\tshared.txt')")"

W="$(fresh_clone)"
git -C "$W" remote set-url origin git@github.com:octo/demo
git -C "$W" config url."$REMOTE".insteadOf git@github.com:octo/demo
OUT="$(cd "$W" && STUB_GH_URL="$NOWHERE" STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
assert_eq "an SSH origin naming gh's repository ranks" yes "$(has_row "$OUT" "$(printf '1\t3\tshared.txt')")"

W="$(fresh_clone)"
git -C "$W" remote set-url origin git@github.com:me/fork.git
git -C "$W" config url."$REMOTE".insteadOf git@github.com:up/stream.git
# spellchecker:ignore-next-line
OUT="$(cd "$W" && STUB_GH_NWO=up/stream STUB_GH_URL="$NOWHERE" STUB_GH_SSH=git@github.com:up/stream.git \
  STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
assert_eq "an SSH fork clone fetches gh's sshUrl" yes "$(has_row "$OUT" "$(printf '1\t3\tshared.txt')")"

W="$(fresh_clone)"
# spellchecker:ignore-next-line
OUT="$(cd "$W" && STUB_GH_NWO=up/stream STUB_GH_URL="$NOWHERE" STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" \
  bash "$SCRIPT" --prs 50 2>&1)"
assert_contains "an unfetchable head names its source and git's error" "$OUT" "gap: PR #1 head could not be fetched from $NOWHERE: "
assert_contains "the gap line carries the error text" "$OUT" "nowhere.git"

W="$(fresh_clone)"
: >"$STUB_GH_LOG"
(cd "$W" && STUB_GH_URL=https://ghe.example.com/octo/demo STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" \
  bash "$SCRIPT" --prs 50 --dry-run >/dev/null 2>&1)
assert_contains "a GHES repository is listed as host/owner/repo" "$(cat "$STUB_GH_LOG")" "--repo ghe.example.com/octo/demo"

W="$(fresh_clone)"
OUT="$(cd "$W" && STUB_GH_JSON="$LISTING" PATH="$FAILBIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
RC=$?
assert_exit "a failing merge-tree exits 2" 2 "$RC"
if git -C "$W" cat-file -e "$PR1_SHA^{commit}" 2>/dev/null; then fetched=yes; else fetched=no; fi
assert_eq "the failing run had fetched the heads" yes "$fetched"
assert_eq "run namespace is gone after a failure" 0 "$(ref_count "$W")"

for compat in default 51; do
  W="$(fresh_clone)"
  if [[ "$compat" == default ]]; then
    run "$W" "$HOSTILE_LISTING" --prs 50
  else
    OUT="$(cd "$W" && BASH_COMPAT=51 STUB_GH_JSON="$HOSTILE_LISTING" PATH="$BIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
    RC=$?
  fi
  assert_exit "hostile names exit 0 ($compat)" 0 "$RC"
  markers="$(find "$W" -maxdepth 1 -name 'pwned-*' | wc -l | tr -d ' ')"
  assert_eq "hostile names run no command ($compat)" 0 "$markers"
  for h in "${HOSTILE[@]}"; do
    want=0
    [[ "$h" == 'a[1]' ]] && want=1
    assert_eq "hostile name ranked verbatim: $h ($compat)" yes "$(has_row "$OUT" "$(printf '%d\t3\t%s' "$want" "$h")")"
  done
done

W="$(fresh_clone)"
git -C "$W" config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
before="$(git -C "$W" for-each-ref refs/remotes)"
run "$W" "$LISTING" --prs 50
assert_exit "a pull-head fetch refspec run exits 0" 0 "$RC"
assert_eq "remote-tracking refs are unchanged by the run" "$before" "$(git -C "$W" for-each-ref refs/remotes)"

W="$(fresh_clone)"
run "$W" "$TAB_LISTING" --prs 50
assert_exit "a path with a tab exits 2" 2 "$RC"
assert_eq "a path with a tab creates no ref" 0 "$(ref_count "$W")"

W="$(fresh_clone)"
OUT="$(cd "$W" && PATH="$NOGH" "$BASH" "$SCRIPT" --prs 50 2>&1)"
RC=$?
assert_exit "missing gh exits 2" 2 "$RC"
assert_contains "missing gh names co-change mining" "$OUT" "co-change"

W="$(fresh_clone)"
OUT="$(cd "$W" && STUB_GH_FAIL=1 STUB_GH_JSON="$LISTING" PATH="$BIN:$PATH" bash "$SCRIPT" --prs 50 2>&1)"
RC=$?
assert_exit "a failed gh read exits 2" 2 "$RC"

W="$(fresh_clone)"
for args in "--prs abc" "--prs 0" "" "--prs 5 --max-pairs 0" "--prs 5 --repo bad" "--prs 5 --repo a/b/c" "--prs 5 --bogus" "--prs 5 --exclude"; do
  # shellcheck disable=SC2086 # word splitting builds the argument list
  run "$W" "$LISTING" $args
  assert_exit "usage error exits 2: '$args'" 2 "$RC"
done

mkdir -p "$TEST_TMPDIR/plain"
run "$TEST_TMPDIR/plain" "$LISTING" --prs 5
assert_exit "outside a repository exits 2" 2 "$RC"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
