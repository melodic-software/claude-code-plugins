#!/usr/bin/env bash
# test-scope: plugins/guardrails/hooks/*.sh plugins/guardrails/hooks/yaml-subset.awk plugins/guardrails/lib/verification/*.sh
# Contract tests for the guardrails pre-push entry git-hooks/pre-push-content.sh:
# a secret or machine-specific path that a pushed commit adds blocks with
# "<path>:<line>: <message> (commit <id>)", also when a later commit of the same
# push removes it again; a pushed commit with nothing to find, the same token
# under an exempt path, a commit the remote's tracking refs already hold, the
# remote's lines and files a merge brings in and a deletion do not block; a merge's own
# conflict resolution is judged, in a file another parent holds as a symlink
# too, and its git process count does not grow with the other side's diff; a
# NUL file is judged whole; a symlink a commit turns into a regular file is
# judged whole and the reverse is not judged; a declined entry checks nothing; --worktree
# covers uncommitted files; and through the plugin's vendored installer a real
# `git push` of a dossier/<key>-<slug> branch (the dossier_branch_prefix
# default) to a bare remote fails on a planted token and passes once that
# commit is dropped from the range. The entry's run time on a 20-commit push is
# printed and held to the check-placement convention's 60 s pre-push budget.
# test-scope: plugins/guardrails/git-hooks/content-scan.sh plugins/guardrails/git-hooks/entries.json plugins/guardrails/lib/git-hooks/check-lib.sh plugins/guardrails/lib/git-hooks/install.mjs
# test-scope: plugins/guardrails/lib/secret-detection/secret-patterns.sh plugins/guardrails/lib/path-detection/hardcoded-path-patterns.sh plugins/guardrails/lib/path-detection/machine-path-patterns.sh
# test-scope: plugins/guardrails/.claude-plugin/plugin.json plugins/guardrails/git-hooks/pre-commit-content.sh plugins/guardrails/git-hooks/reference-verify.sh plugins/guardrails/git-hooks/commit-msg-convention.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT
# Env-supplied config (a caller's core.hooksPath, say) would reach every repo below.
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/pre-push-content.sh"
PLUGIN="$(cd "$HERE/.." && pwd)"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Fixtures are assembled at run time, so no real-shape token or machine path
# sits in this file's own bytes for a scanner to find. Never fold them into
# literals.
SL='/'
FAKE_GHP="ghp_$(printf 'A%.0s' {1..36})"
FAKE_LINUX="${SL}home${SL}alice${SL}projects${SL}demo${SL}src${SL}main.sh"
BRANCH="dossier/GH-7579-pre-push-secrets"
ZERO=0000000000000000000000000000000000000000
HINT='guardrails: remove the secrets or machine-specific paths above from the commits that add them (use a placeholder, an environment variable or a portable path, and rewrite each named commit: a later commit that deletes the text still publishes it), then push again.'

n=0
# new_repo: a repository whose main is pushed to a bare origin, with
# origin/HEAD set, on a new $BRANCH from main.
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q --bare -b main "$WORK/r$n.git"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  printf 'line one\nline two\n' >"$REPO/notes.md"
  git -C "$REPO" add notes.md
  git -C "$REPO" commit -q -m seed --no-verify
  git -C "$REPO" remote add origin "$WORK/r$n.git"
  git -C "$REPO" push -q --no-verify origin main 2>/dev/null
  git -C "$REPO" remote set-head origin main >/dev/null
  git -C "$REPO" switch -q -c "$BRANCH"
}

commit_text() { # <path> <text> <message>: writes <path> and commits it
  mkdir -p "$(dirname "$REPO/$1")"
  printf '%s' "$2" >"$REPO/$1"
  git -C "$REPO" add -- "$1"
  git -C "$REPO" commit -q -m "$3" --no-verify
}

short() { git -C "$REPO" rev-parse --short=12 "$1"; }

# push_check <local-sha> <remote-sha> -> "<rc>|<stderr>", the way git runs a
# pre-push hook for $BRANCH: remote name and url as args, refs on stdin.
push_check() {
  local err rc
  err="$(cd "$REPO" && printf 'refs/heads/%s %s refs/heads/%s %s\n' "$BRANCH" "$1" "$BRANCH" "$2" |
    bash "$CHECK" origin "$WORK/r$n.git" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

new_push() { push_check "$(git -C "$REPO" rev-parse HEAD)" "$ZERO"; }

new_repo
commit_text notes.md $'line one\nline two\nclean addition\n' "clean"
expect "a new branch whose commits add nothing to find passes" "0|" "$(new_push)"

new_repo
commit_text notes.md $'line one\nline two\ntoken='"$FAKE_GHP"$'\n' "plant"
planted="$(short HEAD)"
expect "a pushed commit that adds a token blocks, naming the line and the commit" \
  "1|notes.md:3: secret or credential pattern: GitHub PAT (commit $planted)
$HINT" "$(new_push)"

new_repo
commit_text notes.md $'line one\nline two\nsee '"$FAKE_LINUX"$' here\n' "path"
expect "a pushed commit that adds a home path blocks" \
  "1|notes.md:3: machine-specific path (Linux user path detected) (commit $(short HEAD))
$HINT" "$(new_push)"

# Each commit is judged on its own: the tip no longer holds the token, but the
# push would publish the commit that does.
new_repo
commit_text notes.md $'line one\nline two\ntoken='"$FAKE_GHP"$'\n' "plant"
planted="$(short HEAD)"
commit_text notes.md $'line one\nline two\n' "unplant"
expect "a token one commit adds and a later commit removes still blocks" \
  "1|notes.md:3: secret or credential pattern: GitHub PAT (commit $planted)
$HINT" "$(new_push)"

new_repo
commit_text tests/fixtures/token.txt "token=$FAKE_GHP"$'\n' "fixture"
expect "a token under tests/fixtures/ passes, as secret-pattern-detection exempts it" "0|" "$(new_push)"

# An existing branch: only the commits after the remote's tip are judged.
new_repo
commit_text notes.md $'line one\nline two\ntoken='"$FAKE_GHP"$'\n' "plant"
git -C "$REPO" push -q --no-verify origin "$BRANCH" 2>/dev/null
old="$(git -C "$REPO" rev-parse HEAD)"
commit_text other.md $'clean\n' "clean"
expect "an update judges only the commits after the remote's tip" "0|" \
  "$(push_check "$(git -C "$REPO" rev-parse HEAD)" "$old")"

# A new branch stacked on a pushed branch: the commits a tracking ref holds are
# on the remote already.
new_repo
commit_text notes.md $'line one\nline two\ntoken='"$FAKE_GHP"$'\n' "plant"
git -C "$REPO" push -q --no-verify origin "$BRANCH:other" 2>/dev/null
commit_text other.md $'clean\n' "clean"
expect "a commit a remote-tracking ref holds is not judged again" "0|" "$(new_push)"

expect "a deletion checks nothing" "0|" "$(push_check "$ZERO" "$(git -C "$REPO" rev-parse HEAD)")"

# A merge of the remote's main brings in its lines, which are on the remote
# already; only what the merge adds against every parent is judged.
new_repo
git -C "$REPO" switch -q main
commit_text main.md "see $FAKE_LINUX"$'\n' "main path"
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
git -C "$REPO" switch -q "$BRANCH"
commit_text branch.md $'clean\n' "branch"
git -C "$REPO" merge -q --no-edit --no-verify origin/main >/dev/null 2>&1
expect "a merge's lines from the remote's main are not judged again" "0|" "$(new_push)"

# A file holding a NUL byte is judged whole, past the ranges: one a merge
# takes unchanged from the remote's main is not judged again either.
new_repo
git -C "$REPO" switch -q main
printf 'MZ\0token=%s\n' "$FAKE_GHP" >"$REPO/n.bin"
git -C "$REPO" add n.bin
git -C "$REPO" commit -q -m "main binary" --no-verify
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
git -C "$REPO" switch -q "$BRANCH"
commit_text branch.md $'clean\n' "branch"
git -C "$REPO" merge -q --no-edit --no-verify origin/main >/dev/null 2>&1
expect "a merge's binary file from the remote's main is not judged again" "0|" "$(new_push)"

new_repo
git -C "$REPO" switch -q -c side
commit_text side.md $'side\n' "side"
git -C "$REPO" switch -q "$BRANCH"
commit_text branch.md $'clean\n' "branch"
git -C "$REPO" merge -q --no-commit --no-ff side >/dev/null 2>&1
printf 'resolved\ntoken=%s\n' "$FAKE_GHP" >"$REPO/side.md"
git -C "$REPO" add side.md
git -C "$REPO" commit -q --no-edit --no-verify
expect "a token a merge's own resolution adds blocks" \
  "1|side.md:2: secret or credential pattern: GitHub PAT (commit $(short HEAD))
$HINT" "$(new_push)"

# In one file both sides changed, the path the remote's main brings passes and
# the path the merge's resolution adds blocks.
new_repo
git -C "$REPO" switch -q main
commit_text notes.md $'line one\nmain change\nsee '"$FAKE_LINUX"$' here\n' "main path"
git -C "$REPO" push -q --no-verify origin main 2>/dev/null
git -C "$REPO" switch -q "$BRANCH"
commit_text notes.md $'line one\nbranch change\n' "branch"
git -C "$REPO" merge -q --no-commit origin/main >/dev/null 2>&1
printf 'line one\nresolved at %s\nsee %s here\n' "${SL}home${SL}bob${SL}build${SL}out.log" "$FAKE_LINUX" >"$REPO/notes.md"
git -C "$REPO" add notes.md
git -C "$REPO" commit -q --no-edit --no-verify
expect "a path a merge's own resolution adds blocks beside one the remote's main brings" \
  "1|notes.md:2: machine-specific path (Linux user path detected) (commit $(short HEAD))
$HINT" "$(new_push)"

# Two merges of one 3-file branch, with integration branches of 20 and 40
# changed files, each merge adding a token of its own. The git processes each
# push starts are counted from a trace, and compared as a difference, not an
# absolute count, so git's own internal spawns cancel out.
new_repo
for i in 1 2 3; do printf 'branch %s\n' "$i" >"$REPO/b$i.md"; done
git -C "$REPO" add -A
git -C "$REPO" commit -q -m branch --no-verify
git -C "$REPO" push -q --no-verify origin "$BRANCH" 2>/dev/null
starts=()
for w in 20 40; do
  git -C "$REPO" switch -q -c "integ$w" main
  for ((i = 1; i <= w; i++)); do printf 'integ %s\n' "$i" >"$REPO/i$i.md"; done
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "integ $w" --no-verify
  git -C "$REPO" push -q --no-verify origin "integ$w" 2>/dev/null
  git -C "$REPO" switch -q -c "merge$w" "$BRANCH"
  git -C "$REPO" merge -q --no-commit --no-ff "integ$w" >/dev/null 2>&1
  printf 'token=%s\n' "$FAKE_GHP" >"$REPO/resolved.md"
  git -C "$REPO" add resolved.md
  git -C "$REPO" commit -q --no-edit --no-verify
  expect "a pushed merge with a $w-file side blocks on its own token" \
    "1|resolved.md:1: secret or credential pattern: GitHub PAT (commit $(short HEAD))
$HINT" "$(GIT_TRACE2_EVENT="$WORK/trace.$w" push_check "$(git -C "$REPO" rev-parse HEAD)" "$ZERO")"
  starts+=("$(grep -c '"event":"start"' "$WORK/trace.$w")")
done
echo "measured: a pushed merge started ${starts[0]} git processes with a 20-file side, ${starts[1]} with a 40-file side"
expect "a pushed merge's git process count does not grow with the other side's diff" yes \
  "$( ((starts[0] > 0 && starts[1] - starts[0] <= 2)) && echo yes)"

# Merges built with plumbing, so no symlink is ever checked out: on Windows
# with core.symlinks=false, an edited checked-out symlink stays at 120000.
# ptree <mode> <name>: a one-file tree holding stdin as <name> at <mode>.
ptree() {
  local blob
  blob="$(git -C "$REPO" hash-object -w --stdin)"
  printf '%s blob %s\t%s\n' "$1" "$blob" "$2" | git -C "$REPO" mktree
}
# pcommit <tree> <parent>...: a commit of <tree> on those parents.
pcommit() {
  local tree=$1 p
  local -a args=()
  shift
  for p in "$@"; do args+=(-p "$p"); done
  git -C "$REPO" commit-tree "${args[@]}" -m plumbing "$tree"
}
# on_remote <name> <commit>: a tracking ref holds <commit>, so only a merge on
# it is pushed.
on_remote() { git -C "$REPO" update-ref "refs/remotes/origin/$1" "$2"; }

new_repo
seed="$(git -C "$REPO" rev-parse HEAD)"
p1="$(pcommit "$(printf 'clean\n' | ptree 100644 t.txt)" "$seed")"
p2="$(pcommit "$(printf 'elsewhere' | ptree 120000 t.txt)" "$seed")"
on_remote p1 "$p1"
on_remote p2 "$p2"
merge="$(pcommit "$(printf 'clean\ntoken=%s\n' "$FAKE_GHP" | ptree 100644 t.txt)" "$p1" "$p2")"
expect "a token in a file a non-first parent holds as a symlink blocks" \
  "1|t.txt:2: secret or credential pattern: GitHub PAT (commit $(short "$merge"))
$HINT" "$(push_check "$merge" "$ZERO")"

p2="$(pcommit "$(printf 'token=%s' "$FAKE_GHP" | ptree 120000 t.txt)" "$seed")"
on_remote p2b "$p2"
merge="$(pcommit "$(printf 'token=%s' "$FAKE_GHP" | ptree 100644 t.txt)" "$p1" "$p2")"
expect "a symlink target turned into a regular file with the same bytes is judged" \
  "1|t.txt:1: secret or credential pattern: GitHub PAT (commit $(short "$merge"))
$HINT" "$(push_check "$merge" "$ZERO")"

# A commit that turns its first parent's symlink into a regular file adds every
# line of it; one that turns a regular file into a symlink adds no content.
new_repo
seed="$(git -C "$REPO" rev-parse HEAD)"
link="$(pcommit "$(printf 'elsewhere' | ptree 120000 t.txt)" "$seed")"
retyped="$(pcommit "$(printf 'clean\ntoken=%s\n' "$FAKE_GHP" | ptree 100644 t.txt)" "$link")"
expect "a pushed commit that turns a symlink into a regular file is judged whole" \
  "1|t.txt:2: secret or credential pattern: GitHub PAT (commit $(short "$retyped"))
$HINT" "$(push_check "$retyped" "$ZERO")"
file="$(pcommit "$(printf 'clean\n' | ptree 100644 t.txt)" "$seed")"
retyped="$(pcommit "$(printf 'token=%s' "$FAKE_GHP" | ptree 120000 t.txt)" "$file")"
expect "a pushed commit that turns a regular file into a symlink is not judged" "0|" \
  "$(push_check "$retyped" "$ZERO")"

b0="$(pcommit "$(printf 'MZ\0base\n' | ptree 100644 n.bin)" "$seed")"
b1="$(pcommit "$(printf 'MZ\0one\n' | ptree 100644 n.bin)" "$b0")"
b2="$(pcommit "$(printf 'MZ\0two\n' | ptree 100644 n.bin)" "$b0")"
on_remote b1 "$b1"
on_remote b2 "$b2"
merge="$(pcommit "$(printf 'MZ\0resolved\ntoken=%s\n' "$FAKE_GHP" | ptree 100644 n.bin)" "$b1" "$b2")"
expect "a binary file the merge's resolution changes is judged whole" \
  "1|n.bin:2: secret or credential pattern: GitHub PAT (commit $(short "$merge"))
$HINT" "$(push_check "$merge" "$ZERO")"

new_repo
printf 'MZ\0%s\n' "$FAKE_LINUX" >"$REPO/path.bin"
git -C "$REPO" add path.bin
git -C "$REPO" commit -q -m "path binary" --no-verify
expect "a non-merge commit's ordinary binary passes" "0|" "$(new_push)"
printf 'MZ\0token=%s\n' "$FAKE_GHP" >"$REPO/token.bin"
git -C "$REPO" add token.bin
git -C "$REPO" commit -q -m "token binary" --no-verify
expect "a non-merge commit's NUL file is judged whole" \
  "1|token.bin:1: secret or credential pattern: GitHub PAT (commit $(short HEAD))
$HINT" "$(new_push)"

new_repo
commit_text notes.md $'line one\nline two\ntoken='"$FAKE_GHP"$'\n' "plant"
git -C "$REPO" config checks.guardrails.pre-push-content.declined true
expect "a declined entry checks nothing" "0|" "$(new_push)"
git -C "$REPO" config --unset checks.guardrails.pre-push-content.declined
git -C "$REPO" config checks.git-hooks.declined true
expect "the master decline key declines it too" "0|" "$(new_push)"
git -C "$REPO" config checks.guardrails.pre-push-content.declined false
expect "the entry's own key beats the master key" 1 "$(new_push | head -c 1)"

# A working-tree file named exactly like a pushed SHA made git read the bare
# revision as ambiguous and exit 128, refusing the push.
new_repo
base_sha="$(git -C "$REPO" rev-parse HEAD)"
commit_text notes.md $'line one\nline two\nclean addition\n' "clean"
tip_sha="$(git -C "$REPO" rev-parse HEAD)"
: >"$REPO/$base_sha"
: >"$REPO/$tip_sha"
expect "files named like the pushed base and tip SHAs do not stop a clean push" "0|" \
  "$(push_check "$tip_sha" "$base_sha")"
commit_text notes.md $'line one\nline two\nclean addition\ntoken='"$FAKE_GHP"$'\n' "plant"
planted="$(short HEAD)"
expect "files named like the pushed base and tip SHAs still let a planted token block" \
  "1|notes.md:4: secret or credential pattern: GitHub PAT (commit $planted)
$HINT" "$(push_check "$(git -C "$REPO" rev-parse HEAD)" "$base_sha")"

new_repo
printf 'token=%s\n' "$FAKE_GHP" >"$REPO/draft.md"
got="$(cd "$REPO" && bash "$CHECK" --worktree 2>&1 >/dev/null)"
expect "--worktree judges an untracked file" "1|draft.md:1: secret or credential pattern: GitHub PAT" \
  "$?|$(head -1 <<<"$got")"

# The run time on a representative push: 20 commits, each changing two files.
new_repo
for i in $(seq 1 20); do
  printf 'entry %s\n' "$i" >>"$REPO/notes.md"
  printf '# Part %s\n\nSome prose for part %s.\n' "$i" "$i" >"$REPO/part-$i.md"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "part $i" --no-verify
done
start=$SECONDS
got="$(new_push)"
took=$((SECONDS - start))
echo "measured: pre-push-content took ${took} s on a 20-commit, 40-file-change push"
expect "the entry passes the 20-commit push" "0|" "$got"
expect "the entry runs within the 60 s pre-push budget" yes "$( ((took < 60)) && echo yes)"

# End to end through the plugin's vendored installer and a real git push.
new_repo
status="$(node "$INSTALL" copy --scope local --entry pre-push-content --repo "$REPO")"
expect "the vendored installer installs the entry" '[{"entry":"pre-push-content","status":"installed"}]' "$status"
for a in content-scan.sh secret-patterns.sh hardcoded-path-patterns.sh machine-path-patterns.sh; do
  expect "the $a asset is installed beside the copy" yes \
    "$(test -f "$REPO/.git/hooks/guardrails/$a" && echo yes)"
done
commit_text notes.md $'line one\nline two\ntoken='"$FAKE_GHP"$'\n' "plant"
git -C "$REPO" push -q origin "$BRANCH" >/dev/null 2>"$WORK/push.err"
rc=$?
echo "planted-token push of $BRANCH: exit $rc"
expect "git push of a dossier branch with a planted token fails" yes "$( ((rc != 0)) && echo yes)"
expect "the failure names the planted line" yes \
  "$(grep -q '^notes.md:3: secret or credential pattern: GitHub PAT (commit ' "$WORK/push.err" && echo yes)"
expect "the remote did not get the branch" no \
  "$(git -C "$WORK/r$n.git" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null && echo yes || echo no)"
git -C "$REPO" reset -q --hard HEAD~1
commit_text notes.md $'line one\nline two\nclean\n' "clean"
git -C "$REPO" push -q origin "$BRANCH" >/dev/null 2>"$WORK/push.err"
rc=$?
echo "push of $BRANCH after the planted commit is dropped: exit $rc"
expect "with the planted commit dropped from the range, git push passes" 0 "$rc"
commit_text notes.md $'line one\nline two\nclean\ntoken='"$FAKE_GHP"$'\n' "plant again"
commit_text notes.md $'line one\nline two\nclean\n' "unplant"
git -C "$REPO" push -q origin "$BRANCH" >/dev/null 2>"$WORK/push.err"
rc=$?
expect "git push fails when one commit adds the token and a later one removes it" yes "$( ((rc != 0)) && echo yes)"
expect "verify reports the entry ok" "ok	pre-push-content" \
  "$(node "$INSTALL" verify --repo "$REPO" | grep 'pre-push-content')"

echo "pre-push-content: $PASS passed, $FAIL failed"
((FAIL == 0))
