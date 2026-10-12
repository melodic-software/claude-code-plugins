#!/usr/bin/env bash
# Integration tests for push-branch.sh — the §2.4.1 push gate sequence
# (resolve-fetch -> resolve-push -> conditional `-u` push -> re-resolve-fetch).
#
# resolve-remote.test.sh exercises the resolver in ISOLATION; it cannot catch a
# gate that resolves correctly yet still writes the branch's upstream to the
# wrong place — the pushDefault-only triangular clobber lived in exactly that
# gap. These cases drive REAL pushes into REAL bare remotes
# and assert the destination that received the branch AND whether the conditional
# `-u` rewrote the branch's upstream (branch.<name>.remote AND branch.<name>.merge
# — `git push -u` writes both), the observables a clobber would corrupt.
#
# The suite pins the refined invariant in BOTH directions, so neither strawman
# passes:
#   * bootstrap POSITIVELY asserts `-u` fired (branch.remote set from unset) —
#     rejects an always-plain-push implementation.
#   * non-triangular, local-only `.`, and merge-only tracking assert an EXISTING
#     upstream's merge ref survives the push — rejects an always-`-u`
#     implementation, the resolved-name-only gate that shipped `-u` whenever
#     fetch==push, and a remote-only "no upstream" probe that misses a branch
#     tracking origin/<ref> via branch.<name>.merge with the remote unset.
#   * the fetch-ambiguous case proves a failed fetch resolution degrades to a
#     plain push (no clobber), never an abort.

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUSH_BRANCH="${SCRIPT_DIR}/push-branch.sh"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"

for s in "$PUSH_BRANCH" "$RESOLVER"; do
  if [[ ! -x "$s" ]]; then
    echo "FAIL: missing or not executable: $s" >&2
    exit 1
  fi
done

PASS=0
FAIL=0
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

BRANCH="feat/x"

# A gh stand-in for the acting-login read push-branch.sh makes to tell a lane
# from an operator: an operator login unless PB_LOGIN says otherwise, and a
# failed read when PB_LOGIN_FAIL is set. Lane cases add a git stand-in that
# records a push instead of sending it.
REAL_GIT="$(type -P git)"
SHIM="$WORKDIR/shim"
LOG="$WORKDIR/log"
mkdir -p "$SHIM" "$LOG"
cat >"$SHIM/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "api --hostname")
    [[ -z ${PB_LOGIN_FAIL:-} ]] || exit 1
    echo "${PB_LOGIN:-example-user}"
    ;;
  "pr view") echo "feat/b example-org/app" ;;
  *) exit 99 ;;
esac
EOF
cat >"$SHIM/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ \$a == push && -n \${PB_RECORD_PUSH:-} ]]; then
    printf '%s\n' "\$@" >"$LOG/push.argv"
    pwd -P >"$LOG/push.cwd"
    exit 0
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SHIM/gh" "$SHIM/git"
export PATH="$SHIM:$PATH"

# Build a working clone under $WORKDIR/$1 with `feat/x` checked out (one commit),
# plus a bare remote per remaining `name` arg. The clone's `origin` is a bare
# repo of its own so a real push has somewhere to land. Echoes the clone path.
make_clone() {
  local name="$1"
  shift
  local base="$WORKDIR/$name"
  mkdir -p "$base"
  git init -q --bare "$base/origin.git"
  git clone -q "$base/origin.git" "$base/wc" 2>/dev/null
  git -C "$base/wc" config user.email test@example.com
  git -C "$base/wc" config user.name Test
  git -C "$base/wc" commit -q --allow-empty -m init
  git -C "$base/wc" checkout -q -b "$BRANCH"
  for extra in "$@"; do
    git init -q --bare "$base/$extra.git"
    git -C "$base/wc" remote add "$extra" "$base/$extra.git"
  done
  echo "$base/wc"
}

check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       got    '$got'"
    echo "       wanted '$want'"
    FAIL=$((FAIL + 1))
  fi
}

# 'yes' if $2.git has the branch ref, else 'no'.
has_branch() {
  if git -C "$1.git" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null 2>&1; then
    echo yes
  else
    echo no
  fi
}

# branch_config <worktree> <key> — `branch.<BRANCH>.<key>` as git has it, or the
# literal UNSET when the key is absent (git exits 1 and prints nothing).
branch_config() {
  git -C "$1" config "branch.${BRANCH}.$2" 2>/dev/null || echo UNSET
}

# 1. Fresh-branch bootstrap: no branch.remote, no push config. Fetch and push
#    both fall back to origin -> equal -> `-u` fires, tracking is bootstrapped.
wc=$(make_clone bootstrap)
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "bootstrap: -u fired, branch.remote set to origin" "$(branch_config "$wc" remote)" "origin"
check "bootstrap: origin received the branch" "$(has_branch "$WORKDIR/bootstrap/origin")" "yes"

# 2. Non-triangular, established upstream: branch.remote=origin already set, with
#    a NON-default merge ref (tracks origin/main). Push resolves origin too, but
#    the upstream already exists -> plain push -> the merge ref must survive. An
#    always-`-u` (or resolved-name-only) gate would rewrite it to refs/heads/feat/x.
wc=$(make_clone nontri)
git -C "$wc" config "branch.${BRANCH}.remote" origin
git -C "$wc" config "branch.${BRANCH}.merge" refs/heads/main
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "non-triangular: branch.remote stays origin" "$(branch_config "$wc" remote)" "origin"
check "non-triangular: merge ref preserved (not rewritten by -u)" "$(branch_config "$wc" merge)" "refs/heads/main"
check "non-triangular: origin received the branch" "$(has_branch "$WORKDIR/nontri/origin")" "yes"

# 3. Triangular via branch.<name>.pushRemote: fetch upstream, push fork.
#    Resolved remotes differ -> plain push -> branch.remote preserved as upstream.
wc=$(make_clone tri-pushremote upstream fork)
git -C "$wc" config "branch.${BRANCH}.remote" upstream
git -C "$wc" config "branch.${BRANCH}.pushRemote" fork
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "pushRemote-tri: fetch remote preserved (upstream)" "$(branch_config "$wc" remote)" "upstream"
check "pushRemote-tri: fork received the branch" "$(has_branch "$WORKDIR/tri-pushremote/fork")" "yes"
check "pushRemote-tri: origin did NOT receive the branch" "$(has_branch "$WORKDIR/tri-pushremote/origin")" "no"

# 4. THE #442 REGRESSION: pushDefault-only triangular. branch.remote UNSET,
#    remote.pushDefault=fork, origin present. Fetch falls back to origin, push
#    resolves fork. Resolved remotes differ -> plain push -> branch.remote stays
#    UNSET, so the next fetch/rebase still targets origin (no silent clobber).
wc=$(make_clone tri-pushdefault fork)
git -C "$wc" config remote.pushDefault fork
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "pushDefault-tri: branch.remote NOT clobbered (stays unset)" "$(branch_config "$wc" remote)" "UNSET"
check "pushDefault-tri: next fetch still resolves origin" "$(cd "$wc" && bash "$RESOLVER")" "origin"
check "pushDefault-tri: fork received the branch" "$(has_branch "$WORKDIR/tri-pushdefault/fork")" "yes"
check "pushDefault-tri: origin did NOT receive the branch" "$(has_branch "$WORKDIR/tri-pushdefault/origin")" "no"

# 5. Fetch ambiguous, push determinate: 2+ non-origin remotes, no origin,
#    remote.pushDefault=fork. Fetch resolution fails (empty) -> treated as
#    != push -> plain push to fork, never an abort, never a clobber.
wc=$(make_clone ambiguous fork upstream)
git -C "$wc" remote remove origin
git -C "$wc" config remote.pushDefault fork
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
push_exit=$?
check "fetch-ambiguous: push-branch.sh did not abort" "$push_exit" "0"
check "fetch-ambiguous: branch.remote not written" "$(branch_config "$wc" remote)" "UNSET"
check "fetch-ambiguous: fork received the branch" "$(has_branch "$WORKDIR/ambiguous/fork")" "yes"

# 6. Local-only `.` upstream: branch.remote=. (tracks the local repo), merge
#    tracks refs/heads/main, only origin configured. The resolver normalizes `.`
#    to origin for BOTH modes, so a resolved-name-only gate would see fetch==push
#    and fire `-u`, clobbering the deliberate local-only upstream. Because the
#    upstream literally exists, the refined gate pushes plain: both keys survive.
wc=$(make_clone dot-upstream)
git -C "$wc" config "branch.${BRANCH}.remote" .
git -C "$wc" config "branch.${BRANCH}.merge" refs/heads/main
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "dot-upstream: branch.remote stays '.' (local-only preserved)" "$(branch_config "$wc" remote)" "."
check "dot-upstream: merge ref preserved (not rewritten by -u)" "$(branch_config "$wc" merge)" "refs/heads/main"
check "dot-upstream: origin received the branch" "$(has_branch "$WORKDIR/dot-upstream/origin")" "yes"

# 7. Merge-only tracking: branch.merge set, branch.remote UNSET (valid — Git
#    defaults the remote to origin, so the branch tracks origin/main). Both
#    resolvers fall back to origin, so a remote-only "no existing upstream" probe
#    reads the branch as fresh and fires `-u`, replacing the merge ref. The gate
#    must treat a set merge ref as an existing upstream too -> plain push -> the
#    merge ref survives.
wc=$(make_clone merge-only)
git -C "$wc" config "branch.${BRANCH}.merge" refs/heads/main
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "merge-only: branch.remote not written (stays unset)" "$(branch_config "$wc" remote)" "UNSET"
check "merge-only: merge ref preserved (not rewritten by -u)" "$(branch_config "$wc" merge)" "refs/heads/main"
check "merge-only: origin received the branch" "$(has_branch "$WORKDIR/merge-only/origin")" "yes"

# 8. --pr from another worktree: the session sits in worktree A (feat/x) while
#    the PR being readied is on worktree B (feat/b), whose new commit is not yet
#    pushed. `--pr <n>` must push the PR's head branch (from a stubbed
#    `gh pr view`), never A's branch, and a PR whose head has no local branch
#    must exit non-zero instead of pushing the cwd's branch.
wc=$(make_clone pr-worktree)
git -C "$wc" push -q -u origin "$BRANCH" 2>/dev/null
wt_b="$WORKDIR/pr-worktree/wt-b"
git -C "$wc" worktree add -q -b feat/b "$wt_b" 2>/dev/null
git -C "$wt_b" commit -q --allow-empty -m "merge base into b"
stub="$WORKDIR/pr-worktree/bin"
mkdir -p "$stub"
cat >"$stub/gh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == api ]] && echo example-user && exit 0
[[ "$*" == *" 42 "* ]] && echo "feat/b pr-worktree/origin" && exit 0
[[ "$*" == *" 43 "* ]] && echo "feat/missing pr-worktree/origin" && exit 0
[[ "$*" == *" 44 "* ]] && echo "feat/b someone/fork" && exit 0
[[ "$*" == *" 45 "* ]] && echo "--mirror pr-worktree/origin" && exit 0
[[ "$*" == "pr view  "* ]] && echo "feat/x pr-worktree/origin" && exit 0
exit 1
STUB
chmod +x "$stub/gh"
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 42) >/dev/null 2>&1
check "pr-worktree: --pr 42 exits 0" "$?" "0"
check "pr-worktree: origin holds B's head commit" \
  "$(git -C "$WORKDIR/pr-worktree/origin.git" rev-parse --verify --quiet refs/heads/feat/b)" \
  "$(git -C "$wt_b" rev-parse HEAD)"
missing_exit=zero
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 43) >/dev/null 2>&1 || missing_exit=nonzero
check "pr-worktree: head branch with no local branch exits non-zero" "$missing_exit" "nonzero"
# `gh pr view ""` resolves the cwd branch's PR (the stub answers feat/x, which
# exists locally), so an empty number must stop before gh is asked.
empty_exit=zero
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr "") >/dev/null 2>&1 || empty_exit=nonzero
check "pr-worktree: --pr with no number exits non-zero" "$empty_exit" "nonzero"
# A fork PR whose head name matches a local branch must not push that branch
# to a remote that is not the PR's head repository.
fork_exit=zero
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 44) >/dev/null 2>&1 || fork_exit=nonzero
check "pr-worktree: head repository other than the push remote exits non-zero" "$fork_exit" "nonzero"
# A head branch named like a git option never reaches git push.
git -C "$wc" update-ref refs/heads/--mirror HEAD
dash_exit=zero
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 45) >/dev/null 2>&1 || dash_exit=nonzero
check "pr-worktree: head branch starting with '-' exits non-zero" "$dash_exit" "nonzero"

# 9. Inside a lane, meaning the acting gh login is a GitHub App login
#    (`<slug>[bot]`, the loop-lane identity contract), the push goes to
#    lane-push.sh: its constructed https URL for the repository the push remote
#    names, from the worktree holding the branch, never the remote itself, and
#    no upstream is written. Expected URL and refspec: the lane-push contract.
LANE="example-lane[bot]"
lane_run() {
  rm -f "$LOG"/*
  (cd "$1" && shift && PB_LOGIN="$LANE" PB_RECORD_PUSH=1 bash "$PUSH_BRANCH" "$@") >/dev/null 2>&1
  RC=$?
}
lane_dest() {
  if [[ -f "$LOG/push.argv" ]]; then tail -2 "$LOG/push.argv" | paste -sd' '; else echo NONE; fi
}
wc=$(make_clone lane)
git -C "$wc" remote set-url origin git@github.com:example-org/app.git
lane_run "$wc"
check "lane: exit 0" "$RC" "0"
check "lane: pushed through lane-push.sh (helper reset first)" \
  "$(head -2 "$LOG/push.argv" 2>/dev/null | paste -sd' ')" "-c credential.helper="
check "lane: pushed to the constructed https URL" "$(lane_dest)" \
  "https://github.com/example-org/app.git HEAD:refs/heads/$BRANCH"
check "lane: no upstream written" "$(branch_config "$wc" remote)" "UNSET"

# --pr in a lane: the PR's head, from the worktree that has it checked out.
wt_l="$WORKDIR/lane/wt-b"
git -C "$wc" worktree add -q -b feat/b "$wt_l" 2>/dev/null
lane_run "$wc" --pr 46
check "lane --pr: pushes the PR's head branch" "$(lane_dest)" \
  "https://github.com/example-org/app.git HEAD:refs/heads/feat/b"
check "lane --pr: pushes from the PR worktree" "$(cat "$LOG/push.cwd" 2>/dev/null)" "$(cd "$wt_l" && pwd -P)"

# A lane whose push remote is not a github.com URL cannot be handed over: it
# is refused, and nothing is pushed by either path.
wc=$(make_clone lane-local)
lane_run "$wc"
check "lane, non-GitHub remote: exits non-zero" "$([[ $RC != 0 ]] && echo nonzero || echo zero)" "nonzero"
check "lane, non-GitHub remote: lane-push.sh pushed nothing" "$(lane_dest)" "NONE"
check "lane, non-GitHub remote: the remote did not receive the branch" "$(has_branch "$WORKDIR/lane-local/origin")" "no"

# A branch checked out in no worktree has no HEAD for lane-push.sh: refused.
wc=$(make_clone lane-idle)
git -C "$wc" remote set-url origin https://github.com/example-org/app.git
git -C "$wc" branch -q feat/idle
lane_run "$wc" feat/idle
check "lane, idle branch: exits non-zero" "$([[ $RC != 0 ]] && echo nonzero || echo zero)" "nonzero"
check "lane, idle branch: nothing pushed" "$(lane_dest)" "NONE"

# An operator login keeps the operator path: the remote receives the branch
# through plain git, lane-push.sh is not involved.
wc=$(make_clone operator)
rm -f "$LOG"/*
(cd "$wc" && PB_LOGIN=operator-example bash "$PUSH_BRANCH") >/dev/null 2>&1
check "operator: the remote received the branch by plain git" "$(has_branch "$WORKDIR/operator/origin")" "yes"

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
