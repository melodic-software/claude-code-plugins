#!/usr/bin/env bash
# test-scope: scripts/check-comment-lint.sh plugins/code-tidying/git-hooks/* plugins/code-tidying/scripts/comment-settings.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GITHUB_EVENT_NAME HEAD_SHA BASE_REF

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SUT="$HERE/check-comment-lint.sh"
TEAM=docs/conventions/code-tidying.yaml

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

real_py=""
while IFS= read -r candidate; do
  if "$candidate" -c 'import pygments' 2>/dev/null; then
    real_py="$candidate"
    break
  fi
done < <(type -ap python3)
if [[ -z "$real_py" ]]; then
  echo "FAIL - no python3 on PATH can import pygments, which the comment lint needs" >&2
  exit 1
fi
mkdir "$TMP/bin"
ln -s "$real_py" "$TMP/bin/python3"
PATH="$TMP/bin:$PATH"

fails=0
check() {
  if [[ "$3" == "$2" ]]; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n  want: %q\n  got:  %q\n' "$1" "$2" "$3" >&2
    fails=$((fails + 1))
  fi
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q --no-verify -m "$2"
}

new_clone() {
  local origin="$TMP/origin.$1" clone="$TMP/clone.$1"
  git init -q -b main "$origin"
  mkdir -p "$origin/plugins/code-tidying" "$origin/docs/conventions" "$origin/src"
  cp -R "$ROOT/plugins/code-tidying/git-hooks" "$ROOT/plugins/code-tidying/scripts" "$ROOT/plugins/code-tidying/lib" \
    "$origin/plugins/code-tidying/"
  printf 'comment_posture: necessary\ncomment_lint: %s\n' "$2" >"$origin/$TEAM"
  printf 'x = 1\n' >"$origin/src/app.py"
  commit_all "$origin" base
  git clone -q "$origin" "$clone"
  git -C "$clone" checkout -q -b feature
  printf '%s\n' "$clone"
}

planted() { printf 'y = 2  %s restates the assignment\n' '#'; }
linked() { printf 'y = 2  %s https://example.com/limits/42\n' '#'; }

run_gate() {
  (cd "$1" && GITHUB_EVENT_NAME="${2:-pull_request}" HEAD_SHA="$(git -C "$1" rev-parse HEAD)" BASE_REF=main bash "$SUT" 2>&1)
}

clone="$(new_clone decline block)"
planted >>"$clone/src/app.py"
commit_all "$clone" planted
out="$(run_gate "$clone" push)"
check 'another event exits 0' '0' "$?"
check 'another event says why' '1' "$(grep -c 'declined on a push event' <<<"$out")"

out="$(run_gate "$clone")"
check 'a planted comment fails the pull request' '1' "$?"
check 'the finding names the file, the line and the fix' '1' \
  "$(grep -c '^src/app.py:2: comment outside the necessary posture: delete it' <<<"$out")"
check 'the worktree is removed' '1' "$(git -C "$clone" worktree list | wc -l | tr -d ' ')"

clone="$(new_clone quiet block)"
linked >>"$clone/src/app.py"
commit_all "$clone" linked
out="$(run_gate "$clone")"
check 'an allowed shape passes' '0' "$?"
check 'an allowed shape prints no finding' '0' "$(grep -c 'comment outside' <<<"$out")"

clone="$(new_clone lowered block)"
planted >>"$clone/src/app.py"
printf 'comment_posture: necessary\ncomment_lint: off\n' >"$clone/$TEAM"
commit_all "$clone" 'planted, level lowered'
run_gate "$clone" >/dev/null
check 'a branch cannot lower its own level' '1' "$?"

clone="$(new_clone personal block)"
planted >>"$clone/src/app.py"
printf 'comment_posture: explanatory\n' >"$clone/docs/conventions/code-tidying.local.yaml"
commit_all "$clone" 'planted, personal override committed'
run_gate "$clone" >/dev/null
check 'a committed personal override cannot switch the lint off' '1' "$?"

clone="$(new_clone rehomed block)"
planted >>"$clone/src/app.py"
mkdir -p "$clone/own"
printf 'comment_lint: off\n' >"$clone/own/code-tidying.yaml"
printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in %s.\n<!-- END GENERATED: convention-home -->\n' "\`own\`" >"$clone/AGENTS.md"
commit_all "$clone" 'planted, convention home moved'
run_gate "$clone" >/dev/null
check 'a branch cannot move the convention home to its own team file' '1' "$?"

pointer() {
  printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in %s.\n<!-- END GENERATED: convention-home -->\n' "\`$1\`"
}
clone="$(new_clone renamed off)"
mkdir "$TMP/origin.renamed/team"
printf 'comment_posture: necessary\ncomment_lint: block\n' >"$TMP/origin.renamed/team/code-tidying.yaml"
pointer team >"$TMP/origin.renamed/AGENTS.md"
commit_all "$TMP/origin.renamed" 'the base binds its home to team'
git -C "$clone" fetch -q origin
git -C "$clone" reset -q --hard origin/main
git -C "$clone" mv team new-team
pointer new-team >"$clone/AGENTS.md"
planted >>"$clone/src/app.py"
commit_all "$clone" 'planted, the home directory renamed'
run_gate "$clone" >/dev/null
check 'a branch that renames the home directory still gets the base level' '1' "$?"

clone="$(new_clone linked-out block)"
planted >>"$clone/src/app.py"
printf 'keep\n' >"$TMP/outside.txt"
ln -s "$TMP/outside.txt" "$clone/docs/conventions/code-tidying.local.yaml"
commit_all "$clone" 'planted, a symlink where a settings file goes'
run_gate "$clone" >/dev/null
check 'a planted symlink leaves the file it points at untouched' 'keep' "$(cat "$TMP/outside.txt")"

clone="$(new_clone raised off)"
planted >>"$clone/src/app.py"
printf 'comment_posture: necessary\ncomment_lint: block\n' >"$clone/$TEAM"
commit_all "$clone" 'planted, level raised'
run_gate "$clone" >/dev/null
check 'a level the branch sets takes effect only once merged' '0' "$?"

clone="$(new_clone moved block)"
linked >>"$clone/src/app.py"
commit_all "$clone" linked
planted >"$TMP/origin.moved/src/other.py"
commit_all "$TMP/origin.moved" 'base moves ahead with a comment of its own'
git -C "$clone" fetch -q origin
out="$(run_gate "$clone")"
check 'a comment the base added after the branch point is not the branch'"'"'s' '0' "$?"

(cd "$clone" && GITHUB_EVENT_NAME=pull_request HEAD_SHA=HEAD BASE_REF=main bash "$SUT" >/dev/null 2>&1)
check 'a head that is no commit id is a usage error' '2' "$?"

if ((fails > 0)); then
  printf '%d check(s) failed\n' "$fails" >&2
  exit 1
fi
echo "all checks passed"
