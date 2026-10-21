#!/usr/bin/env bash
# Tests for collect-patch.sh on throwaway repositories. Each fixture commits
# a gated head, changes the working tree as an activity would, and the patch
# must rebuild that tree when applied to a fresh checkout of the head.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECT="$SCRIPT_DIR/collect-patch.sh"

# Keep the developer's own git configuration, and any inherited repository
# location, out of every fixture.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
new_repo() {
  R="$(mktemp -d "$TMP/repo.XXXXXX")"
  git init -q -b main "$R"
  tg config core.autocrlf false
  put keep.txt 'keep\n'
  put edit.txt 'one\ntwo\n'
  put gone.txt 'gone\n'
  put .gitignore '*.log\n'
  tg add -A
  tg commit -q -m head
  HEAD_SHA=$(tg rev-parse HEAD)
  PATCH="$TMP/out.$RANDOM/patch.diff"
  mkdir -p "$(dirname "$PATCH")"
}
# run_collect [<head>]: runs from the checkout as the runner does; sets OUT,
# ERR and RC.
run_collect() {
  local head=${1-$HEAD_SHA}
  RC=0
  OUT=$(cd "$R" && bash "$COLLECT" "$head" "$PATCH" 2>"$TMP/err") || RC=$?
  ERR=$(cat "$TMP/err")
}
field() { sed -n "s/^$1=//p" <<<"$OUT"; }
# The SHA-256 by an implementation other than the script's.
sha256_of() { python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
# apply_to_fresh: applies the patch to a fresh clone of the gated head and
# compares that tree with the fixture's, ignored files aside.
apply_to_fresh() {
  local fresh="$TMP/fresh.$RANDOM"
  git clone -q --no-checkout "$R" "$fresh"
  git -C "$fresh" checkout -q --detach "$HEAD_SHA"
  APPLY_RC=0
  git -C "$fresh" apply --index --binary "$PATCH" 2>"$TMP/apply-err" || APPLY_RC=$?
  SAME=yes
  diff -r --exclude=.git --exclude='*.log' "$R" "$fresh" >/dev/null 2>&1 || SAME=no
}

echo '# clean'
new_repo
put ignored.log 'build output\n'
run_collect
check 'clean: exit 0' 0 "$RC"
check 'clean: state is empty' empty "$(field state)"
check 'clean: no SHA-256' '' "$(field sha256)"
check 'clean: no patch file' no "$([[ -e $PATCH ]] && echo yes || echo no)"

echo '# planted patch file'
# A file already at the patch path is not the activity's patch.
new_repo
printf 'planted\n' >"$PATCH"
run_collect
check 'planted: state is empty' empty "$(field state)"
check 'planted: the planted file is removed' no "$([[ -e $PATCH ]] && echo yes || echo no)"

echo '# edits, additions, deletions'
new_repo
put edit.txt 'one\nTWO\n'
put new/dir/added.txt 'added and never staged\n'
rm "$R/gone.txt"
put ignored.log 'build output\n'
run_collect
check 'edits: exit 0' 0 "$RC"
check 'edits: state is written' written "$(field state)"
check 'edits: sha256 is the patch file'"'"'s SHA-256' "$(sha256_of "$PATCH")" "$(field sha256)"
apply_to_fresh
check 'edits: the patch applies to the gated head' 0 "$APPLY_RC"
check 'edits: the applied tree matches the activity'"'"'s tree' yes "$SAME"
check 'edits: an ignored file is not in the patch' 0 "$(grep -c 'ignored.log' "$PATCH" || true)"
check 'edits: the real index is untouched' '' "$(tg diff --cached --name-only)"
check 'edits: the untracked file stays untracked' '?? new/' "$(tg status --porcelain | grep '^??')"

echo '# binary'
new_repo
printf '\x00\x01\x02\xff\xfe' >"$R/blob.bin"
run_collect
check 'binary: state is written' written "$(field state)"
check 'binary: the patch carries a binary hunk' 1 "$(grep -c '^GIT binary patch' "$PATCH")"
apply_to_fresh
check 'binary: the patch applies' 0 "$APPLY_RC"
check 'binary: the applied tree matches' yes "$SAME"

echo '# committed and staged'
# The activity was told to commit nothing; a commit or a staged change is
# still part of what it changed against the gated head.
new_repo
put edit.txt 'committed\n'
tg commit -q -am 'model commit'
put staged.txt 'staged\n'
tg add staged.txt
run_collect
check 'committed: state is written' written "$(field state)"
apply_to_fresh
check 'committed: the patch applies to the gated head' 0 "$APPLY_RC"
check 'committed: the applied tree matches' yes "$SAME"

echo '# a commit that undoes itself'
new_repo
put edit.txt 'temporary\n'
tg commit -q -am 'temporary'
put edit.txt 'one\ntwo\n'
run_collect
check 'undone: state is empty' empty "$(field state)"

echo '# repository config'
# Config the activity could set does not change the patch's form.
new_repo
tg config diff.noprefix true
tg config color.diff always
tg config color.ui always
tg config diff.external /bin/false
tg config diff.renames copies
tg config core.quotePath true
git -C "$R" mv keep.txt moved.txt
put edit.txt 'one\nTWO\n'
run_collect
check 'config: exit 0' 0 "$RC"
check 'config: no colour codes' 0 "$(grep -c $'\e' "$PATCH" || true)"
check 'config: no rename headers' 0 "$(grep -c '^rename ' "$PATCH" || true)"
check 'config: a/ and b/ prefixes' 'diff --git a/edit.txt b/edit.txt' "$(grep '^diff --git a/edit.txt' "$PATCH")"
apply_to_fresh
check 'config: the patch applies' 0 "$APPLY_RC"
check 'config: the applied tree matches' yes "$SAME"

echo '# planted git config, attributes and hooks'
# Each plant writes a marker when git runs it; none may run, and the patch
# holds the bytes on disk, never what a clean filter would stage.
planted() {
  local name=$1
  run_collect
  check "$name: exit 0" 0 "$RC"
  check "$name: nothing planted ran" no "$([[ -e $MARK ]] && echo yes || echo no)"
  check "$name: the patch holds the bytes on disk" 1 "$(grep -c '^+on disk$' "$PATCH")"
}
hook() {
  mkdir -p "$1"
  printf '#!/bin/sh\ntouch "%s"\n' "$MARK" >"$1/$2"
  chmod +x "$1/$2"
}
new_repo
MARK="$TMP/ran.filter"
tg config filter.x.clean "touch '$MARK'; printf 'staged by the filter\\n'"
mkdir -p "$R/.git/info"
printf 'edit.txt filter=x\n' >"$R/.git/info/attributes"
put edit.txt 'on disk\n'
planted 'a filter in .git/config named by .git/info/attributes'
new_repo
MARK="$TMP/ran.include"
printf '[filter "y"]\n\tclean = touch %s; cat\n' "'$MARK'" >"$R/included"
tg config include.path "$R/included"
tg config includeIf."gitdir:$R/".path "$R/included"
put .gitattributes 'edit.txt filter=y\n'
put edit.txt 'on disk\n'
planted 'a filter only an include or includeIf defines, named by a worktree .gitattributes'
new_repo
MARK="$TMP/ran.hooks"
hook "$R/.git/hooks" post-index-change
hook "$R/hooks" post-index-change
tg config core.hooksPath "$R/hooks"
put edit.txt 'on disk\n'
planted 'a post-index-change hook in .git/hooks and in core.hooksPath'
new_repo
MARK="$TMP/ran.fsmonitor"
hook "$R/.git" monitor
tg config core.fsmonitor "$R/.git/monitor"
put edit.txt 'on disk\n'
planted 'a core.fsmonitor command'

echo '# unsafe input'
new_repo
put edit.txt 'changed\n'
for bad in '' 'HEAD' 'main' "${HEAD_SHA:0:12}" "${HEAD_SHA^^}" "-$HEAD_SHA" "${HEAD_SHA}0"; do
  run_collect "$bad"
  check "unsafe input: a head given as '$bad' is refused" 2 "$RC"
done
run_collect "$(printf '%040d' 0)"
check 'unsafe input: a head the repository lacks fails' 1 "$RC"
check 'unsafe input: the error names the cause' "collect-patch.sh: the head $(printf '%040d' 0) is not a commit here" "$ERR"
run_collect "$(tg rev-parse HEAD:edit.txt)"
check 'unsafe input: a blob given as the head fails' 1 "$RC"
RC=0
(cd "$R" && bash "$COLLECT" "$HEAD_SHA") >/dev/null 2>&1 || RC=$?
check 'unsafe input: a missing patch path is refused' 2 "$RC"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all collect-patch.sh tests passed'
