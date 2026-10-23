#!/usr/bin/env bash
# Tests for context.sh on throwaway repositories: a `pr` branch (the gated
# head) and `main` (the trusted base) merged with conflicts, as prepare.sh
# leaves them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$SCRIPT_DIR/context.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT
FAILED=0
ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}
tg() { git -C "$R" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"; }
put() {
  mkdir -p "$(dirname "$R/$1")"
  printf '%b' "$2" >"$R/$1"
}
commit() {
  tg add -A
  tg commit -q -m "$1"
}
# repo <path> <base> <pr> <main>: both sides edit path, then pr merges main
# with --no-commit; HEAD and BASE name the two sides.
repo() {
  R="$(mktemp -d "$TMP/repo.XXXXXX")"
  git init -q -b main "$R"
  put "$1" "$2"
  commit 'base'
  tg checkout -q -b pr
  put "$1" "$3"
  commit 'pr: the head side of the change'
  tg checkout -q main
  put "$1" "$4"
  commit 'main: the base side of the change'
  tg checkout -q pr
  HEAD=$(tg rev-parse pr) BASE=$(tg rev-parse main)
  git -C "$R" -c user.name=t -c user.email=t@t.t merge -q --no-commit main >/dev/null 2>&1 || true
}
run() {
  OUT="$TMP/out.$RANDOM"
  RC=0
  (cd "$R" && bash "$CONTEXT" "$HEAD" "$BASE" "$OUT" 2>"$TMP/err") || RC=$?
}

echo '# context'
repo 'dir/a b.txt' 'one\n' 'pr\n' 'main\n'
put second.txt 'x\n'
run
check 'exit 0' 0 "$RC"
check 'conflicts.json names the head and base' "$HEAD $BASE" "$(jq -r '"\(.head) \(.base)"' "$OUT/conflicts.json")"
check 'conflicts.json names the merge base' "$(tg merge-base pr main)" "$(jq -r '.merge_bases | join(" ")' "$OUT/conflicts.json")"
check 'one entry per unmerged path, with its directory' 'dir/a b.txt 0000 false' "$(jq -r '.paths[] | "\(.path) \(.dir) \(.omitted)"' "$OUT/conflicts.json")"
check 'the three stages' 'one|pr|main' "$(cat "$OUT/0000/base")|$(cat "$OUT/0000/ours")|$(cat "$OUT/0000/theirs")"
if grep -q '^commit .*' "$OUT/0000/head.log" && grep -q 'pr: the head side' "$OUT/0000/head.log" && grep -q '^+pr$' "$OUT/0000/head.log"; then
  ok 'head.log holds the PR side commits with their patches'
else
  not_ok 'head.log holds the PR side commits with their patches'
fi
if grep -q 'main: the base side' "$OUT/0000/base.log" && ! grep -q 'pr: the head side' "$OUT/0000/base.log"; then
  ok 'base.log holds only the default branch side'
else
  not_ok 'base.log holds only the default branch side'
fi
if ! (echo x >>"$OUT/conflicts.json") 2>/dev/null && ! (touch "$OUT/new") 2>/dev/null; then
  ok 'the directory is read-only'
else
  not_ok 'the directory is read-only'
fi
check 'the merge is still in progress' "$BASE" "$(tg rev-parse MERGE_HEAD)"

echo '# caps'
big=$(head -c 1100000 /dev/zero | tr '\0' 'a')
repo big.txt 'one\n' "$big\n" 'main\n'
run
check 'a stage over 1 MiB is cut with a note' 1 "$(tail -n 1 "$OUT/0000/ours" | grep -c 'cut at 1048576 bytes')"
check 'the cut stage is 1 MiB plus the note' 1 "$(($(stat -c %s "$OUT/0000/ours") < 1048576 + 64 ? 1 : 0))"
# A log over 64 KiB: one long commit message on the head side.
R="$(mktemp -d "$TMP/repo.XXXXXX")"
git init -q -b main "$R"
put l.txt 'one\n'
commit base
tg checkout -q -b pr
put l.txt 'pr\n'
tg add -A
head -c 70000 /dev/zero | tr '\0' 'm' | tg commit -q -F -
tg checkout -q main
put l.txt 'main\n'
commit main
tg checkout -q pr
HEAD=$(tg rev-parse pr) BASE=$(tg rev-parse main)
git -C "$R" -c user.name=t -c user.email=t@t.t merge -q --no-commit main >/dev/null 2>&1 || true
run
check 'a log over 64 KiB is cut with a note' 1 "$(tail -n 1 "$OUT/0000/head.log" | grep -c 'cut at 65536 bytes')"
# Over the 16 MiB total, later files are left out and the entry says so.
R="$(mktemp -d "$TMP/repo.XXXXXX")"
git init -q -b main "$R"
for i in $(seq 1 18); do put "f$i.txt" 'one\n'; done
commit base
tg checkout -q -b pr
for i in $(seq 1 18); do head -c 1000000 /dev/urandom | base64 -w 0 >"$R/f$i.txt"; done
commit pr
tg checkout -q main
for i in $(seq 1 18); do put "f$i.txt" 'main\n'; done
commit main
tg checkout -q pr
HEAD=$(tg rev-parse pr) BASE=$(tg rev-parse main)
git -C "$R" -c user.name=t -c user.email=t@t.t merge -q --no-commit main >/dev/null 2>&1 || true
run
check 'over the total, exit 0' 0 "$RC"
check 'over the total, the last entry is omitted' true "$(jq -r '.paths[-1].omitted' "$OUT/conflicts.json")"
check 'over the total, the first entry is kept' false "$(jq -r '.paths[0].omitted' "$OUT/conflicts.json")"
check 'over the total, at most 16 MiB and the last file are written' 1 "$(($(du -sb "$OUT" | cut -f1) < 16 * 1024 * 1024 + 1200000 ? 1 : 0))"

echo '# refusals'
repo a.txt 'one\n' 'pr\n' 'main\n'
tg merge --abort
run
check 'no merge in progress fails' 1 "$RC"
repo a.txt 'one\n' 'pr\n' 'main\n'
OTHER=$HEAD HEAD=$BASE
run
check 'HEAD other than the gated head fails' 1 "$RC"
HEAD=$OTHER
for bad in pr HEAD --output=x; do
  RC=0
  (cd "$R" && bash "$CONTEXT" "$bad" "$BASE" "$TMP/o.$RANDOM" 2>/dev/null) || RC=$?
  check "a head given as '$bad' is refused" 1 "$RC"
done
mkdir "$TMP/exists"
RC=0
(cd "$R" && bash "$CONTEXT" "$HEAD" "$BASE" "$TMP/exists" 2>/dev/null) || RC=$?
check 'an existing out directory is refused' 1 "$RC"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all context.sh tests passed'
