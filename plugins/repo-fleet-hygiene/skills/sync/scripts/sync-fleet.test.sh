#!/usr/bin/env bash
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sync-fleet.sh"
HELPER="$SCRIPT_DIR/../../../../source-control/scripts/worktree-create.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }
# expect <name> <detail> <command...>: pass when the command succeeds.
expect() {
  local name="$1" detail="$2"
  shift 2
  if "$@"; then pass "$name"; else fail "$name" "$detail"; fi
}
# shellcheck disable=SC2329  # invoked by name, as expect's predicate
has() { [[ "$1" == *"$2"* ]]; }
# shellcheck disable=SC2329  # invoked by name, as expect's predicate
is() { [[ "$1" == "$2" ]]; }

git_identity() {
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
  git -C "$1" config commit.gpgsign false
}

commit_file() {
  local repo="$1" name="$2"
  printf '%s\n' "$name" >"$repo/$name"
  git -C "$repo" add "$name"
  git -C "$repo" commit -q -m "$name"
}

bare="$TMP/remote.git"
git init -q --bare -b main "$bare"
seed="$TMP/seed"
git init -q -b main "$seed"
git_identity "$seed"
commit_file "$seed" README.md
git -C "$seed" remote add origin "$bare"
git -C "$seed" push -q origin main

clone="$TMP/clone"
git clone -q "$bare" "$clone"
git_identity "$clone"

mkdir -p "$TMP/bare-cwd/1/2/3/4"
if ( cd "$TMP/bare-cwd/1/2/3/4" && REPO_FLEET_GHQ_BIN=/nonexistent bash "$SCRIPT" --project-dir "$TMP" >"$TMP/noscope.out" 2>"$TMP/noscope.err" ); then
  fail "no scope exits 3" "exit 0"
else
  code=$?
  if [[ "$code" -eq 3 ]]; then pass "no scope exits 3"; else fail "no scope exits 3" "exit $code"; fi
fi
noscope_err="$(cat "$TMP/noscope.err")"
for want in "--repo/--root: none given" "ghq not installed" "ghq root --all" "5. ancestor" "6. working directory" "is not in a Git checkout" "remedy: cd into or beside your checkouts" "/repo-fleet-hygiene:setup apply --root <dir>" "remedy: cd into a checkout"; do
  expect "the no-scope message carries: $want" "$noscope_err" has "$noscope_err" "$want"
done

# Advance origin, leave the clone behind.
commit_file "$seed" REMOTE_ONLY.md
git -C "$seed" push -q origin main
before="$(git -C "$clone" rev-parse HEAD)"
dry="$(bash "$SCRIPT" --repo "$clone")"
if [[ "$dry" == *$'ff-only\t'"$clone"* && "$(git -C "$clone" rev-parse HEAD)" == "$before" ]]; then
  pass "dry-run plans ff-only and does not move HEAD"
else
  fail "dry-run plans ff-only and does not move HEAD" "$dry"
fi

explicit_dry="$(bash "$SCRIPT" --repo "$clone" --dry-run)"
expect "--dry-run is accepted and plans the same as the default" "$explicit_dry" is "$explicit_dry" "$dry"
bash "$SCRIPT" --repo "$clone" --dry-run --apply --yes >"$TMP/dryapply.out" 2>"$TMP/dryapply.err"
code=$?
expect "--dry-run with --apply exits 2 and changes nothing" "code=$code" is "$code|$(git -C "$clone" rev-parse HEAD)" "2|$before"

if bash "$SCRIPT" --repo "$clone" --apply >"$TMP/noyes.out" 2>"$TMP/noyes.err"; then
  fail "apply without --yes exits 3" "exit 0"
else
  code=$?
  if [[ "$code" -eq 3 && "$(git -C "$clone" rev-parse HEAD)" == "$before" ]]; then
    pass "apply without --yes changes nothing"
  else
    fail "apply without --yes changes nothing" "exit $code"
  fi
fi

if bash "$SCRIPT" --config "$TMP/missing.conf" >/dev/null 2>&1; then
  fail "a missing --config fails" "exit 0"
else
  code=$?
  if [[ "$code" -eq 2 ]]; then pass "a missing --config fails"; else fail "a missing --config fails" "exit $code"; fi
fi

mkdir -p "$TMP/cfg"
printf '[fleet]\n\trepo = ../clone\n' >"$TMP/cfg/fleet.conf"
relative="$(cd / && bash "$SCRIPT" --config "$TMP/cfg/fleet.conf")"
if [[ "$relative" == *$'ff-only\t'"$TMP/cfg/../clone"* || "$relative" == *$'ff-only\t'"$clone"* ]]; then
  pass "a relative fleet.repo resolves against the config directory"
else
  fail "a relative fleet.repo resolves against the config directory" "$relative"
fi

mkdir -p "$TMP/drive/.cargo/git/checkouts"
git clone -q "$bare" "$TMP/drive/.cargo/git/checkouts/dep"
git clone -q "$bare" "$TMP/drive/app"
rooted="$(bash "$SCRIPT" --root "$TMP/drive")"
if [[ "$rooted" == *"$TMP/drive/app"* && "$rooted" != *".cargo"* ]]; then
  pass "a --root walk skips package-manager cache checkouts"
else
  fail "a --root walk skips package-manager cache checkouts" "$rooted"
fi

git clone -q "$bare" "$TMP/drive/app/.git/inner"
pruned="$(bash "$SCRIPT" --root "$TMP/drive")"
expect "a --root walk does not descend into a .git directory" "$pruned" \
  is "$([[ "$pruned" == *"/.git/inner"* ]] && echo found)" ""

mkdir -p "$TMP/skipdrive/vendor" "$TMP/skipdrive/foo"
git clone -q "$bare" "$TMP/skipdrive/vendor/dep"
git clone -q "$bare" "$TMP/skipdrive/foo/dep"
git clone -q "$bare" "$TMP/skipdrive/app"
printf '[fleet]\n\tskip = foo\n' >"$TMP/skip-replace.conf"
replaced="$(bash "$SCRIPT" --root "$TMP/skipdrive" --config "$TMP/skip-replace.conf")"
expect "fleet.skip stops discovery descending into the named directory" "$replaced" \
  is "$([[ "$replaced" == *"$TMP/skipdrive/foo/dep"* ]] && echo found)" ""
expect "fleet.skip replaces the default set, so a repo under vendor/ is found" "$replaced" \
  has "$replaced" "$TMP/skipdrive/vendor/dep"
printf '[fleet]\n\tskipAppend = foo\n' >"$TMP/skip-append.conf"
appended="$(bash "$SCRIPT" --root "$TMP/skipdrive" --config "$TMP/skip-append.conf")"
expect "fleet.skipAppend prunes the appended directory" "$appended" \
  is "$([[ "$appended" == *"$TMP/skipdrive/foo/dep"* ]] && echo found)" ""
expect "fleet.skipAppend keeps the defaults, so vendor/ is still pruned" "$appended" \
  is "$([[ "$appended" == *"$TMP/skipdrive/vendor/dep"* ]] && echo found)" ""
expect "fleet.skipAppend keeps ordinary repos" "$appended" has "$appended" "$TMP/skipdrive/app"
printf '[fleet]\n\tskip = a/b\n' >"$TMP/skip-bad.conf"
bash "$SCRIPT" --root "$TMP/skipdrive" --config "$TMP/skip-bad.conf" >/dev/null 2>&1
expect "a path-shaped fleet.skip entry is refused with exit 2" "code=$?" is "$?" 2

skipped="$(bash "$SCRIPT" --root "$TMP/skipdrive" --skip foo)"
expect "--skip prunes the named directory" "$skipped" \
  is "$([[ "$skipped" == *"$TMP/skipdrive/foo/dep"* ]] && echo found)" ""
expect "--skip replaces the default set, so a repo under vendor/ is found" "$skipped" \
  has "$skipped" "$TMP/skipdrive/vendor/dep"
extended="$(bash "$SCRIPT" --root "$TMP/skipdrive" --extend-skip foo)"
expect "--extend-skip prunes the named directory and keeps the defaults" "$extended" \
  is "$([[ "$extended" == *"$TMP/skipdrive/foo/dep"* || "$extended" == *"$TMP/skipdrive/vendor/dep"* ]] && echo found)" ""

mkdir -p "$TMP/skipdrive/bar"
git clone -q "$bare" "$TMP/skipdrive/bar/dep"
printf 'foo\n\nbar\r\n' >"$TMP/skip.list"
listed="$(bash "$SCRIPT" --root "$TMP/skipdrive" --skip-from "$TMP/skip.list")"
expect "--skip-from prunes every listed name, blank and CRLF lines included" "$listed" \
  is "$([[ "$listed" == *"$TMP/skipdrive/foo/dep"* || "$listed" == *"$TMP/skipdrive/bar/dep"* ]] && echo found)" ""
expect "--skip-from keeps ordinary repos" "$listed" has "$listed" "$TMP/skipdrive/app"

bash "$SCRIPT" --root "$TMP/skipdrive" --skip-from "$TMP/no-such.list" >/dev/null 2>&1
expect "--skip-from on a missing file exits 2" "code=$?" is "$?" 2
bash "$SCRIPT" --root "$TMP/skipdrive" --skip '' >/dev/null 2>&1
expect "--skip '' exits 2" "code=$?" is "$?" 2

printf '%s\n\n%s\r\n' "$clone" "$TMP/skipdrive/app" >"$TMP/repos.list"
fromfile="$(cd / && bash "$SCRIPT" --repos-from "$TMP/repos.list" --project-dir "$TMP/cfg")"
expect "--repos-from FILE plans exactly the listed repos" "$fromfile" \
  is "$(printf '%s\n' "$fromfile" | grep -c "^ff-only")" 2
expect "--repos-from FILE reports the listed repo count" "$fromfile" has "$fromfile" "repos: 2"
fromstdin="$(printf '%s\n' "$clone" | bash "$SCRIPT" --repos-from -)"
expect "--repos-from - reads stdin" "$fromstdin" has "$fromstdin" "repos: 1"
bash "$SCRIPT" --repos-from "$TMP/no-such.list" >/dev/null 2>&1
expect "--repos-from on a missing file exits 2" "code=$?" is "$?" 2
printf '[fleet]\n\trepo = %s\n' "$TMP/seed" >"$TMP/scoped.conf"
scoped="$(bash "$SCRIPT" --repos-from "$TMP/repos.list" --config "$TMP/scoped.conf")"
expect "--repos-from skips the config scope rung" "$scoped" \
  is "$([[ "$scoped" == *"$TMP/seed"* ]] && echo found)" ""

git clone -q --bare "$bare" "$TMP/evil.git"
git -C "$TMP/evil.git" update-ref refs/heads/-evil refs/heads/main
git -C "$TMP/evil.git" symbolic-ref HEAD refs/heads/-evil
git clone -q "$bare" "$TMP/victim"
git -C "$TMP/victim" remote set-url origin "$TMP/evil.git"
evil="$(bash "$SCRIPT" --repo "$TMP/victim")"
code=$?
if [[ "$evil" == *$'skip\t'"$TMP/victim"$'\t\tls-remote'* ]]; then
  pass "a remote default branch starting with a dash is refused"
else
  fail "a remote default branch starting with a dash is refused" "$evil"
fi
expect "a dry-run that plans a skip still exits 0" "code=$code" is "$code" 0

evil_applied="$(bash "$SCRIPT" --repo "$TMP/victim" --apply --yes)"
code=$?
expect "a skip line names the git exit" "$evil_applied" \
  has "$evil_applied" $'skipped\t'"$TMP/victim"$'\tls-remote\tgit-exit='
expect "a skip line carries a remedy" "$evil_applied" has "$evil_applied" $'\tremedy='
expect "a skipped repo exits 1" "code=$code" is "$code" 1

mkdir "$TMP/plain"
plain="$(bash "$SCRIPT" --repo "$TMP/plain" --apply --yes)"
expect "a directory git cannot read is skipped with git's own exit status" "$plain" \
  has "$plain" $'skipped\t'"$TMP/plain"$'\tdubious-or-unreadable\tgit-exit=128\tremedy='

applied="$(bash "$SCRIPT" --repo "$clone" --apply --yes)"
code=$?
if [[ "$applied" == *$'applied\t'"$clone"* && "$(git -C "$clone" rev-parse HEAD)" == "$(git -C "$bare" rev-parse main)" ]]; then
  pass "apply --yes fast-forwards"
else
  fail "apply --yes fast-forwards" "$applied"
fi
expect "exit 0 when every repo applied" "code=$code $applied" is "$code" 0

dirty="$TMP/dirty"
git clone -q "$bare" "$dirty"
git_identity "$dirty"
git -C "$dirty" switch -q -c feature
printf 'park-me\n' >"$dirty/DIRTY.md"
printf 'staged\n' >"$dirty/STAGED.md"
git -C "$dirty" add STAGED.md
wtroot="$TMP/worktrees"
mkdir -p "$wtroot"

nowt="$(bash "$SCRIPT" --repo "$dirty" --apply --yes)"
code=$?
if [[ "$nowt" == *$'skip\t'"$dirty"$'\t\tworktree-create-missing'* && "$(git -C "$dirty" branch --show-current)" == "feature" &&
  -f "$dirty/DIRTY.md" && -z "$(git -C "$dirty" stash list)" ]]; then
  pass "a park with no worktree helper is skipped before anything changes"
else
  fail "a park with no worktree helper is skipped before anything changes" "$nowt"
fi
expect "a plan-rule skip exits 1 with git-exit=none and a remedy" "code=$code $nowt" \
  has "$nowt" $'skipped\t'"$dirty"$'\tworktree-create-missing\tgit-exit=none\tremedy='
expect "a plan-rule skip exits 1" "code=$code" is "$code" 1
expect "the no-helper remedy names the helper argument and the manual route" "$nowt" \
  has "$nowt" "--worktree-create <path to source-control's scripts/worktree-create.sh>"
expect "the no-helper remedy names the manual worktree route" "$nowt" \
  has "$nowt" "/source-control:worktree create --existing-branch"
rooted_only="$(bash "$SCRIPT" --repo "$dirty" --worktree-root "$wtroot")"
expect "a worktree root alone does not enable a park" "$rooted_only" \
  has "$rooted_only" $'skip\t'"$dirty"$'\t\tworktree-create-missing'

# The helper is named only by --worktree-create, and only a file called worktree-create.sh.
mkdir "$TMP/fail" "$TMP/helper-dir" "$TMP/helper-dir/worktree-create.sh"
printf 'exit 1\n' >"$TMP/fail/worktree-create.sh"
printf 'exit 0\n' >"$TMP/fail-create.sh"
for bad in "$TMP/fail-create.sh" "$TMP/absent/worktree-create.sh" "$TMP/helper-dir/worktree-create.sh"; do
  bash "$SCRIPT" --repo "$dirty" --worktree-create "$bad" >"$TMP/bad.out" 2>"$TMP/bad.err"
  code=$?
  expect "--worktree-create $bad is refused with exit 2" "code=$code $(cat "$TMP/bad.err")" is "$code" 2
  expect "a refused --worktree-create names the rule and plans nothing" "$(cat "$TMP/bad.err") $(cat "$TMP/bad.out")" \
    is "$(grep -c 'must name an existing file called worktree-create.sh' "$TMP/bad.err")|$(wc -c <"$TMP/bad.out" | tr -d ' ')" "1|0"
done

# The source-control plugin next door is never probed: a decoy in its place stays unread.
layout="$TMP/layout"
mkdir -p "$layout/source-control/scripts"
cp -R "$SCRIPT_DIR/../../.." "$layout/repo-fleet-hygiene"
printf '#!/usr/bin/env bash\ntouch "%s"\necho "%s"\n' "$TMP/decoy.ran" "$TMP/decoy-worktree" >"$layout/source-control/scripts/worktree-create.sh"
for sibling in "a decoy" no; do
  [[ "$sibling" != no ]] || rm -rf "$layout/source-control"
  copy="$(bash "$layout/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh" --repo "$dirty" --apply --yes --worktree-root "$wtroot")"
  code=$?
  expect "with $sibling source-control sibling, a park is skipped as worktree-create-missing" "code=$code $copy" \
    has "$copy" $'skipped\t'"$dirty"$'\tworktree-create-missing\tgit-exit=none'
  expect "with $sibling source-control sibling, nothing is stashed and no helper ran" "$(git -C "$dirty" stash list)" \
    is "$([[ -e "$TMP/decoy.ran" ]] && echo ran)|$(git -C "$dirty" stash list)" "|"
done

broken="$(bash "$SCRIPT" --repo "$dirty" --apply --yes --worktree-root "$wtroot" --worktree-create "$TMP/fail/worktree-create.sh")"
if [[ "$broken" == *$'skipped\t'"$dirty"$'\tworktree\trestored'* && "$(git -C "$dirty" branch --show-current)" == "feature" &&
  -f "$dirty/DIRTY.md" && "$(git -C "$dirty" diff --cached --name-only)" == "STAGED.md" && -z "$(git -C "$dirty" stash list)" ]]; then
  pass "a failed worktree create puts the branch and the stash back"
else
  fail "a failed worktree create puts the branch and the stash back" "$broken"
fi

parked="$(bash "$SCRIPT" --repo "$dirty" --apply --yes --worktree-root "$wtroot" --worktree-create "$HELPER")"
if [[ "$(git -C "$dirty" branch --show-current)" == "main" && "$parked" == *park-existing* ]]; then
  wt="$(printf '%s\n' "$parked" | awk -F '\t' '$1 == "applied" && $3 == "park-existing" { print $4 }')"
  if [[ -f "$wt/DIRTY.md" && "$(git -C "$wt" branch --show-current)" == "feature" &&
    "$(git -C "$wt" diff --cached --name-only)" == "STAGED.md" ]]; then
    pass "dirty non-default branch is parked in a worktree"
  else
    fail "dirty non-default branch is parked in a worktree" "wt=$wt parked=$parked"
  fi
else
  fail "dirty non-default branch is parked in a worktree" "$parked"
fi

# Test double for worktree-create.sh. It records its arguments in $STUB_LOG.
# STUB_FOREIGN=1 makes another session push a stash first, STUB_REAL=1 creates
# the real worktree and prints its path, and STUB_EXIT ends the run with that
# status.
mkdir "$TMP/stub"
STUB="$TMP/stub/worktree-create.sh"
export STUB_LOG="$TMP/stub.args"
cat >"$STUB" <<'EOF'
#!/usr/bin/env bash
args=("$@")
printf '%s\n' "$*" >"$STUB_LOG"
repo=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == --repo-dir ]] && repo="$2"
  shift
done
if [[ -n "${STUB_FOREIGN:-}" ]]; then
  printf 'x\n' >"$repo/FOREIGN.md"
  git -C "$repo" stash push -q -u -m foreign-session
fi
if [[ -n "${STUB_REAL:-}" ]]; then
  wt="$(bash "$REAL_HELPER" "${args[@]}")" || exit $?
  printf '%s\n' "$wt"
fi
printf 'stub: warning, exiting %s\n' "${STUB_EXIT:-0}" >&2
exit "${STUB_EXIT:-0}"
EOF
export REAL_HELPER="$HELPER"

# dirty_clone <dir> [<branch>]: a clone with an untracked and a staged file, on <branch> when given.
dirty_clone() {
  git clone -q "$bare" "$1"
  git_identity "$1"
  [[ -z "${2:-}" ]] || git -C "$1" switch -q -c "$2"
  printf 'park-me\n' >"$1/DIRTY.md"
  printf 'staged\n' >"$1/STAGED.md"
  git -C "$1" add STAGED.md
}

# run_park <repo> [<worktree-root>]: apply with the stub helper under the
# caller's STUB_* variables, passing --worktree-root only when a root is given;
# sets OUT, ERR, CODE, ARGS (what the helper was called with), and WT (the
# applied worktree path).
run_park() {
  local root=()
  [[ -z "${2:-}" ]] || { mkdir -p "$2"; root=(--worktree-root "$2"); }
  rm -f "$STUB_LOG"
  OUT="$(bash "$SCRIPT" --repo "$1" --apply --yes ${root[@]+"${root[@]}"} --worktree-create "$STUB" 2>"$TMP/park.err")"
  CODE=$?
  ERR="$(cat "$TMP/park.err")"
  ARGS="$(cat "$STUB_LOG" 2>/dev/null)"
  WT="$(printf '%s\n' "$OUT" | awk -F '\t' '$1 == "applied" { print $4 }')"
  WT="${WT:-$TMP/no-worktree}"
}

stash_subjects() { git -C "$1" stash list --format=%gs; }
# shellcheck disable=SC2329  # invoked by name, as expect's predicate
restored_in_place() { [[ -f "$1/DIRTY.md" && ! -e "$1/FOREIGN.md" && "$(git -C "$1" diff --cached --name-only)" == "STAGED.md" ]]; }

# Another session pushes a stash between the park and the apply.
repo_a="$TMP/park-a"
dirty_clone "$repo_a" feature-a
STUB_REAL=1 STUB_FOREIGN=1 run_park "$repo_a" "$TMP/wt-a"
d="code=$CODE out=$OUT err=$ERR"
expect "a park applies its own stash by SHA, not the top of the stack" "$d" restored_in_place "$WT"
expect "a park drops only its own stash and the other session's survives" "$d $(stash_subjects "$repo_a")" \
  is "$(stash_subjects "$repo_a")" "On main: foreign-session"
expect "an applied park exits 0" "$d" is "$CODE" 0
expect "--worktree-root reaches the helper as --root" "$d args=$ARGS" has "$ARGS" "--root $TMP/wt-a"

# The same push, then a failed worktree create: unpark must restore its own entry.
repo_b="$TMP/park-b"
dirty_clone "$repo_b" feature-b
STUB_FOREIGN=1 STUB_EXIT=1 run_park "$repo_b" "$TMP/wt-b"
d="code=$CODE out=$OUT err=$ERR"
expect "a failed park skips with restored, the helper status, and a remedy" "$d" \
  has "$OUT" $'skipped\t'"$repo_b"$'\tworktree\trestored\tgit-exit=1\tremedy='
expect "a failed park exits 1" "$d" is "$CODE" 1
expect "unpark restores its own stash by SHA and puts the branch back" "$d" \
  restored_in_place "$repo_b"
expect "unpark leaves the other session's stash alone" "$d $(stash_subjects "$repo_b")" \
  is "$(stash_subjects "$repo_b")" "On main: foreign-session"
expect "unpark returns to the original branch" "$d" is "$(git -C "$repo_b" branch --show-current)" feature-b

# Helper status 3: nothing was created.
repo_c="$TMP/park-c"
dirty_clone "$repo_c" feature-c
STUB_EXIT=3 run_park "$repo_c" "$TMP/wt-c"
d="code=$CODE out=$OUT err=$ERR"
expect "helper exit 3 is unparked and reported with its status" "$d" \
  has "$OUT" $'skipped\t'"$repo_c"$'\tworktree\trestored\tgit-exit=3\tremedy='
expect "helper exit 3 leaves the work in place and the stash empty" "$d" \
  restored_in_place "$repo_c"
expect "helper exit 3 leaves no stash" "$d" is "$(stash_subjects "$repo_c")" ""
expect "helper exit 3 quotes the helper's first stderr line and names the root remedy" "$d" \
  has "$OUT" "(stub: warning, exiting 3); set worktreeroot.path"

# Without --worktree-root the helper gets no --root and resolves the root from the repository.
repo_h="$TMP/park-h"
dirty_clone "$repo_h" feature-h
git -C "$repo_h" config worktreeroot.path "$TMP/wt-h"
STUB_REAL=1 run_park "$repo_h"
d="code=$CODE out=$OUT err=$ERR args=$ARGS"
expect "an unset --worktree-root keeps --root out of the helper call" "$d" \
  is "$([[ " $ARGS " == *" --root "* ]] && echo root)" ""
expect "an unset --worktree-root parks under the repository's worktreeroot.path" "$d" has "$WT" "$TMP/wt-h/"
expect "an unset --worktree-root still parks the work in the worktree" "$d" restored_in_place "$WT"

# The real helper refuses when no root resolves anywhere: unparked, skipped, its message quoted.
repo_i="$TMP/park-i"
dirty_clone "$repo_i" feature-i
OUT="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash "$SCRIPT" --repo "$repo_i" --apply --yes --worktree-create "$HELPER" 2>"$TMP/park.err")"
CODE=$?
d="code=$CODE out=$OUT err=$(cat "$TMP/park.err")"
expect "no root anywhere skips the repo as helper exit 3, restored, with a remedy" "$d" \
  has "$OUT" $'skipped\t'"$repo_i"$'\tworktree\trestored\tgit-exit=3\tremedy=worktree-create.sh exited 3'
expect "no root anywhere leaves the work in place and no stash" "$d" \
  is "$(restored_in_place "$repo_i" && echo in-place)|$(stash_subjects "$repo_i")" "in-place|"

# Helper status 4 and 5 with a path: the worktree exists, so the park continues.
for status in 4 5; do
  repo_s="$TMP/park-s$status"
  dirty_clone "$repo_s" "feature-s$status"
  STUB_REAL=1 STUB_EXIT=$status run_park "$repo_s" "$TMP/wt-s$status"
  d="code=$CODE out=$OUT err=$ERR"
  expect "helper exit $status with a path keeps the worktree and applies the stash" "$d" \
    has "$OUT" $'applied\t'"$repo_s"$'\tpark-existing\t'"$TMP/wt-s$status"
  expect "helper exit $status parks the work in the reported worktree" "$d" \
    restored_in_place "$WT"
  expect "helper exit $status prints the helper's warning as a note" "$d" \
    has "$ERR" "worktree-create.sh exited $status but the worktree exists at $WT"
  expect "helper exit $status leaves no stash and the canonical checkout on main" "$d" \
    is "$(stash_subjects "$repo_s")|$(git -C "$repo_s" branch --show-current)" "|main"
done

# Helper status 4 without a path: nothing usable, so unpark.
repo_d="$TMP/park-d"
dirty_clone "$repo_d" feature-d
STUB_EXIT=4 run_park "$repo_d" "$TMP/wt-d"
d="code=$CODE out=$OUT err=$ERR"
expect "helper exit 4 without a path is unparked and reported" "$d" \
  has "$OUT" $'skipped\t'"$repo_d"$'\tworktree\trestored\tgit-exit=4\tremedy='
expect "helper exit 4 without a path restores the work and leaves no stash" "$d" \
  restored_in_place "$repo_d"

# A dirty default branch parks on a sync-park branch and comes back clean.
repo_e="$TMP/park-e"
dirty_clone "$repo_e"
STUB_REAL=1 run_park "$repo_e" "$TMP/wt-e"
d="code=$CODE out=$OUT err=$ERR"
expect "a dirty default branch is parked on a sync-park branch in a worktree" "$d" \
  has "$(git -C "$WT" branch --show-current)" "sync-park/"
expect "a dirty default branch parks the work and leaves a clean checkout and no stash" "$d" \
  is "$(git -C "$repo_e" status --porcelain)|$(stash_subjects "$repo_e")|$([[ -f "$WT/DIRTY.md" ]] && echo parked)" "||parked"

repo_f="$TMP/park-f"
dirty_clone "$repo_f"
STUB_FOREIGN=1 STUB_EXIT=2 run_park "$repo_f" "$TMP/wt-f"
d="code=$CODE out=$OUT err=$ERR"
expect "a failed default-branch park restores the work by SHA on the default branch" "$d" \
  restored_in_place "$repo_f"
expect "a failed default-branch park drops its sync-park branch and keeps the other stash" "$d" \
  is "$(git -C "$repo_f" branch --show-current)|$(git -C "$repo_f" branch --list 'sync-park/*')|$(stash_subjects "$repo_f")" "main||On main: foreign-session"
expect "a failed default-branch park exits 1" "$d" is "$CODE" 1

# A stash entry that cannot be matched by its marker fails closed.
mkdir "$TMP/shim"
cat >"$TMP/shim/git" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  [[ "\$arg" == push ]] && exit 0
done
exec "$(command -v git)" "\$@"
EOF
chmod +x "$TMP/shim/git"
repo_g="$TMP/park-g"
dirty_clone "$repo_g" feature-g
printf 'x\n' >"$repo_g/PRE.md"
git -C "$repo_g" stash push -q -u -m pre-existing -- PRE.md
OUT="$(PATH="$TMP/shim:$PATH" bash "$SCRIPT" --repo "$repo_g" --apply --yes --worktree-root "$TMP/wt-g" --worktree-create "$STUB" 2>/dev/null)"
CODE=$?
d="code=$CODE out=$OUT"
expect "an unmatched stash marker skips without applying or dropping anything" "$d" \
  has "$OUT" $'skipped\t'"$repo_g"$'\tstash-lookup\tgit-exit=none\tremedy='
expect "an unmatched stash marker exits 1" "$d" is "$CODE" 1
expect "an unmatched stash marker leaves the existing stash and the tree alone" "$d $(stash_subjects "$repo_g")" \
  is "$(stash_subjects "$repo_g")|$(git -C "$repo_g" branch --show-current)|$([[ -f "$repo_g/DIRTY.md" ]] && echo dirty)" "On feature-g: pre-existing|feature-g|dirty"

diverge="$TMP/diverge"
git clone -q "$bare" "$diverge"
git_identity "$diverge"
printf 'local\n' >"$diverge/LOCAL.md"
git -C "$diverge" add LOCAL.md
git -C "$diverge" commit -q -m local
commit_file "$seed" OTHER.md
git -C "$seed" push -q origin main
tip="$(git -C "$diverge" rev-parse HEAD)"
skipped="$(bash "$SCRIPT" --repo "$diverge" --apply --yes)"
code=$?
if [[ "$skipped" == *non-fast-forward* && "$(git -C "$diverge" rev-parse HEAD)" == "$tip" ]]; then
  pass "non-fast-forward is skipped and the local commit stays"
else
  fail "non-fast-forward is skipped and the local commit stays" "$skipped"
fi
expect "a non-fast-forward skip exits 1" "code=$code" is "$code" 1
expect "a non-fast-forward skip line carries git-exit and a remedy" "$skipped" \
  has "$skipped" $'skipped\t'"$diverge"$'\tnon-fast-forward\tgit-exit=128\tremedy='

# The plan names the scope rung that produced each repository, on plan and skipped lines alike.
rung_home="$TMP/rung-home"
mkdir -p "$rung_home"
rung_of() { printf '%s\n' "$1" | awk -F'\t' -v r="$2" '$2 == r { print $NF }'; }
r_repo="$(HOME="$rung_home" bash "$SCRIPT" --repo "$clone")"
expect "--repo plans rung=repo" "$r_repo" is "$(rung_of "$r_repo" "$clone")" "rung=repo"
r_from="$(HOME="$rung_home" bash "$SCRIPT" --repos-from "$TMP/repos.list")"
expect "--repos-from plans rung=repos-from" "$r_from" is "$(rung_of "$r_from" "$clone")" "rung=repos-from"
r_root="$(HOME="$rung_home" bash "$SCRIPT" --root "$TMP/skipdrive")"
expect "--root plans rung=root for a discovered repo" "$r_root" is "$(rung_of "$r_root" "$TMP/skipdrive/app")" "rung=root"
r_bare="$(HOME="$rung_home" bash "$SCRIPT" "$TMP/skipdrive")"
expect "a bare path plans rung=root" "$r_bare" is "$(rung_of "$r_bare" "$TMP/skipdrive/app")" "rung=root"
printf '[fleet]\n\trepo = %s\n' "$clone" >"$TMP/rung.conf"
r_conf="$(HOME="$rung_home" bash "$SCRIPT" --config "$TMP/rung.conf")"
expect "fleet config plans rung=config" "$r_conf" is "$(rung_of "$r_conf" "$clone")" "rung=config"
r_named="$(HOME="$rung_home" REPO_FLEET_GHQ_BIN=/nonexistent bash "$SCRIPT" --named "$clone")"
expect "--named plans rung=named" "$r_named" is "$(rung_of "$r_named" "$clone")" "rung=named"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$TMP/skipdrive" >"$TMP/ghq-stub"
chmod +x "$TMP/ghq-stub"
r_ghq="$(cd "$TMP/bare-cwd" && HOME="$rung_home" REPO_FLEET_GHQ_BIN="$TMP/ghq-stub" bash "$SCRIPT")"
expect "ghq root --all plans rung=ghq" "$r_ghq" is "$(rung_of "$r_ghq" "$TMP/skipdrive/app")" "rung=ghq"
# Four directories above solo hold no other repository, so the ancestor probe finds nothing.
solo="$TMP/iso/a/b/c/solo"
mkdir -p "$TMP/iso/a/b/c"
git clone -q "$bare" "$solo"
r_cwd="$(cd "$solo" && HOME="$rung_home" REPO_FLEET_GHQ_BIN=/nonexistent bash "$SCRIPT")"
expect "the working directory plans rung=cwd" "$r_cwd" is "$(rung_of "$r_cwd" "$solo")" "rung=cwd"
expect "a lone checkout plans only itself" "$r_cwd" has "$r_cwd" $'repos: 1\n'

# A bare run inside one checkout plans the checkout's sibling fleet, from the checkout root or below it.
mkdir -p "$TMP/fleet"
for name in one two three; do git clone -q "$bare" "$TMP/fleet/$name"; done
mkdir -p "$TMP/fleet/one/sub/dir"
for from in "$TMP/fleet/one" "$TMP/fleet/one/sub/dir"; do
  r_sib="$(cd "$from" && HOME="$rung_home" REPO_FLEET_GHQ_BIN=/nonexistent bash "$SCRIPT")"
  expect "a bare run in ${from#"$TMP"/} plans every sibling checkout" "$r_sib" \
    is "$(printf '%s\n' "$r_sib" | awk -F'\t' '/^[a-z-]+\t/ { printf "%s:%s ", $2, $NF }')" \
    "$TMP/fleet/one:rung=ancestor $TMP/fleet/three:rung=ancestor $TMP/fleet/two:rung=ancestor "
  expect "a bare run in ${from#"$TMP"/} reports 3 repos" "$r_sib" has "$r_sib" $'repos: 3\n'
done

# Discovery is the walker audit uses: it honors fleet.maxDepth and stops at a checkout.
printf '[fleet]\n\tmaxDepth = 1\n' >"$TMP/depth1.conf"
depth1="$(bash "$SCRIPT" --root "$TMP/skipdrive" --config "$TMP/depth1.conf")"
expect "fleet.maxDepth 1 finds a repository one level down" "$depth1" has "$depth1" "$TMP/skipdrive/app"
expect "fleet.maxDepth 1 does not descend two levels" "$depth1" \
  is "$([[ "$depth1" == *"$TMP/skipdrive/foo/dep"* ]] && echo found)" ""
printf '[fleet]\n\tmaxDepth = 13\n' >"$TMP/depth-bad.conf"
bash "$SCRIPT" --root "$TMP/skipdrive" --config "$TMP/depth-bad.conf" >/dev/null 2>&1
expect "fleet.maxDepth outside 1 through 12 exits 2" "code=$?" is "$?" 2
mkdir -p "$TMP/nest"
git clone -q "$bare" "$TMP/nest/outer"
git clone -q "$bare" "$TMP/nest/outer/inner"
nested="$(bash "$SCRIPT" --root "$TMP/nest")"
expect "discovery stops at a checkout, so a repository nested in one is not planned" "$nested" \
  is "$(printf '%s\n' "$nested" | awk -F'\t' '/^[a-z-]+\t/ { printf "%s ", $2 }')" "$TMP/nest/outer "
mkdir -p "$TMP/anc/one" "$TMP/anc/two" "$TMP/anc/plain/deep"
git -C "$TMP/anc/one" init -q
git -C "$TMP/anc/two" init -q
r_anc="$(cd "$TMP/anc/plain/deep" && HOME="$rung_home" REPO_FLEET_GHQ_BIN=/nonexistent bash "$SCRIPT" 2>&1)"
expect "an ancestor holding repositories plans rung=ancestor" "$r_anc" is "$(rung_of "$r_anc" "$TMP/anc/one")" "rung=ancestor"
r_skip="$(HOME="$rung_home" bash "$SCRIPT" --repo "$TMP/no-such-dir")"
expect "a skipped plan line carries the rung" "$r_skip" has "$r_skip" $'skip\t'"$TMP/no-such-dir"$'\t\tnot-a-directory\trung=repo'
r_skipped="$(HOME="$rung_home" bash "$SCRIPT" --repo "$TMP/no-such-dir" --apply --yes)"
expect "a skipped result line ends with the rung" "$r_skipped" has "$r_skipped" $'\tremedy=check the path, then fix or remove it in the fleet config or the --repo and --root arguments\trung=repo'

if [[ "$FAILED" -eq 0 ]]; then
  printf 'OK\n'
  exit 0
fi
printf '%s failed\n' "$FAILED" >&2
exit 1
