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
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"

for s in "${SCRIPT_DIR}/push-branch.sh" "$RESOLVER"; do
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

# A gh stand-in. The acting-login read push-branch.sh makes to tell a lane from
# an operator answers an operator login unless PB_LOGIN says otherwise, and
# fails when PB_LOGIN_FAIL is set. `repo view` names the base repository, and
# `pr view` the PR's head branch and repository (PB_PR_HEAD_REPO, else the
# base): push-branch.sh's own read (`-q`, one line) and lane-push.sh's (`-R`,
# two lines). `api --hostname github.com repos/...` is lane-push.sh's default-branch read. Lane cases add a git
# stand-in that records a push instead of sending it. With PB_GITHUB_ROOT set,
# the git stand-in sends a push for https://github.com/<path> to
# $PB_GITHUB_ROOT/<path>, so a remote can carry a github.com URL (what
# `git remote get-url` reports) and still push into a local bare repository.
REAL_GIT="$(type -P git)"
SHIM="$WORKDIR/shim"
LOG="$WORKDIR/log"
mkdir -p "$SHIM" "$LOG"
cat >"$SHIM/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "api --hostname")
    if [[ $4 == repos/* ]]; then
      printf '%s\nmain\n\n\n' "${4#repos/}"
      exit 0
    fi
    [[ -z ${PB_LOGIN_FAIL:-} ]] || exit 1
    echo "${PB_LOGIN:-example-user}"
    ;;
  "repo view") echo "example-org/app" ;;
  "pr view")
    if [[ " $* " == *" -R "* ]]; then
      printf '%s\n' "${PB_PR_HEAD_REPO:-example-org/app}" feat/b
    else
      echo "feat/b ${PB_PR_HEAD_REPO:-example-org/app}"
    fi
    ;;
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
  if [[ \$a == push && -n \${PB_GITHUB_ROOT:-} ]]; then
    exec "$REAL_GIT" -c "url.\$PB_GITHUB_ROOT/.insteadOf=https://github.com/" \
      -c "url.\$PB_GITHUB_ROOT/.insteadOf=ssh://git@github.com/" \
      -c "url.\$PB_GITHUB_ROOT/.insteadOf=git@github.com:" "\$@"
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SHIM/gh" "$SHIM/git"
export PATH="$SHIM:$PATH"

# push-branch.sh runs from a copy of the plugin's layout, so the lane identity
# preflight it calls (babysit-prs' babysit-postmerge.sh --preflight) is a
# stand-in: it records its arguments and answers in the preflight's JSON shape,
# passing with PB_IDENTITY as the configured identity, else refusing as a
# target that names none. lane-push.sh is the real one.
PLUGIN="$WORKDIR/plugin"
mkdir -p "$PLUGIN/skills/pull-request/scripts" "$PLUGIN/skills/babysit-prs/scripts" "$PLUGIN/scripts"
cp -p "${SCRIPT_DIR}/push-branch.sh" "$RESOLVER" "$PLUGIN/skills/pull-request/scripts/"
cp -p "${SCRIPT_DIR}/../../../scripts/lane-push.sh" "$PLUGIN/scripts/"
cat >"$PLUGIN/skills/babysit-prs/scripts/babysit-postmerge.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$LOG/preflight.argv"
if [[ -n \${PB_IDENTITY:-} ]]; then
  printf '{\n  "ok": true,\n  "identity": "%s"\n}\n' "\$PB_IDENTITY"
  exit 0
fi
printf '{\n  "ok": false,\n  "error": "agent-identity-unconfigured"\n}\n'
exit 2
EOF
chmod +x "$PLUGIN/skills/babysit-prs/scripts/babysit-postmerge.sh"
PUSH_BRANCH="$PLUGIN/skills/pull-request/scripts/push-branch.sh"

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
#    must exit non-zero instead of pushing the cwd's branch. origin carries the
#    github.com URL of the PR's head repository, as a real checkout does.
wc=$(make_clone pr-worktree)
git -C "$wc" push -q -u origin "$BRANCH" 2>/dev/null
git -C "$wc" remote set-url origin https://github.com/pr-worktree/origin.git
export PB_GITHUB_ROOT="$WORKDIR"
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
# --dir pushes the HEAD of that checkout, detached included (a babysit
# worker's worktree), to the PR's head branch.
wt_d="$WORKDIR/pr-worktree/wt-d"
git -C "$wc" worktree add -q --detach "$wt_d" feat/b 2>/dev/null
git -C "$wt_d" commit -q --allow-empty -m "fix on a detached head"
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --dir "$wt_d" --pr 42) >/dev/null 2>&1
check "pr-worktree: --dir --pr exits 0" "$?" "0"
check "pr-worktree: --dir pushed that checkout's detached HEAD to the PR head branch" \
  "$(git -C "$WORKDIR/pr-worktree/origin.git" rev-parse --verify --quiet refs/heads/feat/b)" \
  "$(git -C "$wt_d" rev-parse HEAD)"
# --dir after --pr is the same call, and an argument the script does not take
# refuses instead of being dropped.
git -C "$wt_d" commit -q --allow-empty -m "second fix on a detached head"
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 42 --dir "$wt_d") >/dev/null 2>&1
check "pr-worktree: --pr --dir exits 0" "$?" "0"
check "pr-worktree: --pr --dir pushed that checkout's HEAD to the PR head branch" \
  "$(git -C "$WORKDIR/pr-worktree/origin.git" rev-parse --verify --quiet refs/heads/feat/b)" \
  "$(git -C "$wt_d" rev-parse HEAD)"
for args in "--pr 42 extra" "--pr 42 --bogus" "feat/b extra" "--pr 42 feat/b" "--pr 42 --pr 43" "--dir"; do
  extra_exit=zero
  # shellcheck disable=SC2086 # word-split on purpose: each entry is an argv.
  extra_err=$(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" $args 2>&1 >/dev/null) || extra_exit=nonzero
  check "pr-worktree: '$args' exits non-zero" "$extra_exit" "nonzero"
  check "pr-worktree: '$args' is refused before any push" \
    "$([[ $extra_err == *"push-branch.sh: "*"; not pushing"* ]] && echo refused || echo "$extra_err")" "refused"
done
# The head-repository check reads the URL the push goes to: a push URL that is
# not the PR's head repository refuses even when the fetch URL is.
git init -q --bare "$WORKDIR/pr-worktree/other.git"
git -C "$wc" remote set-url --push origin https://github.com/pr-worktree/other.git
pushurl_exit=zero
(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 42) >/dev/null 2>&1 || pushurl_exit=nonzero
check "pr-worktree: push URL other than the PR head repository exits non-zero" "$pushurl_exit" "nonzero"
check "pr-worktree: the other push URL did not receive the branch" \
  "$(git -C "$WORKDIR/pr-worktree/other.git" rev-parse --verify --quiet refs/heads/feat/b || echo none)" "none"
# The head repository is a github.com repository: a push URL on another host,
# a longer github.com path, or an SSH host alias, that merely ends in
# owner/repo refuses, and refuses at the head-repository check rather than at
# a failed push.
git init -q --bare "$WORKDIR/elsewhere/pr-worktree/origin.git"
for url in "$WORKDIR/elsewhere/pr-worktree/origin.git" \
  https://github.com/elsewhere/pr-worktree/origin.git \
  git@github-work:pr-worktree/origin.git; do
  git -C "$wc" remote set-url --push origin "$url"
  host_exit=zero
  host_err=$(cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --pr 42 2>&1 >/dev/null) || host_exit=nonzero
  check "pr-worktree: push URL $url, not the github.com head repository, exits non-zero" \
    "$host_exit" "nonzero"
  check "pr-worktree: push URL $url is refused by the head-repository check" \
    "$([[ $host_err == *"not PR '42' head repository"* ]] && echo refused || echo "$host_err")" "refused"
  check "pr-worktree: push URL $url did not receive the branch" \
    "$(git -C "$WORKDIR/elsewhere/pr-worktree/origin.git" rev-parse --verify --quiet refs/heads/feat/b || echo none)" "none"
done
# The ssh:// and scp-style github.com forms of the head repository push.
for url in ssh://git@github.com/pr-worktree/origin.git git@github.com:pr-worktree/origin.git; do
  git -C "$wt_d" commit -q --allow-empty -m "push over $url"
  git -C "$wc" remote set-url --push origin "$url"
  (cd "$wc" && PATH="$stub:$PATH" bash "$PUSH_BRANCH" --dir "$wt_d" --pr 42) >/dev/null 2>&1
  check "pr-worktree: push URL $url exits 0" "$?" "0"
  check "pr-worktree: push URL $url pushed the PR head branch" \
    "$(git -C "$WORKDIR/pr-worktree/origin.git" rev-parse --verify --quiet refs/heads/feat/b)" \
    "$(git -C "$wt_d" rev-parse HEAD)"
done
unset PB_GITHUB_ROOT

# 9. Inside a lane, meaning the acting gh login is a GitHub App login
#    (`<slug>[bot]`, the loop-lane identity contract), the push goes to
#    lane-push.sh as the identity the base repository configures, and only
#    after the identity preflight passes for that repository: its constructed
#    https URL for the base repository (or, with --pr, the PR's own head), from
#    the worktree holding the branch, never a remote, and no upstream is
#    written. Expected URL and refspec: the lane-push contract.
LANE="example-lane[bot]"
lane_run() {
  rm -f "$LOG"/*
  (cd "$1" && shift && PB_LOGIN="$LANE" PB_RECORD_PUSH=1 bash "$PUSH_BRANCH" "$@") >/dev/null 2>&1
  RC=$?
}
lane_dest() {
  if [[ -f "$LOG/push.argv" ]]; then tail -2 "$LOG/push.argv" | paste -sd' '; else echo NONE; fi
}
nonzero() { [[ $RC != 0 ]] && echo nonzero || echo zero; }
wc=$(make_clone lane)
git -C "$wc" remote set-url origin git@github.com:example-org/app.git
PB_IDENTITY="$LANE" lane_run "$wc"
check "lane: exit 0" "$RC" "0"
check "lane: the identity preflight ran for the base repository" \
  "$(paste -sd' ' "$LOG/preflight.argv" 2>/dev/null)" "--repo example-org/app --preflight"
check "lane: pushed through lane-push.sh (helper reset first)" \
  "$(head -2 "$LOG/push.argv" 2>/dev/null | paste -sd' ')" "-c credential.helper="
check "lane: pushed to the constructed https URL" "$(lane_dest)" \
  "https://github.com/example-org/app.git HEAD:refs/heads/$BRANCH"
check "lane: no upstream written" "$(branch_config "$wc" remote)" "UNSET"

# The push binds to the configured identity, not to whatever login acts: a
# configured identity other than the acting login is refused by lane-push.sh.
PB_IDENTITY="other-lane[bot]" lane_run "$wc"
check "lane, acting login not the configured identity: exits non-zero" "$(nonzero)" "nonzero"
check "lane, acting login not the configured identity: nothing pushed" "$(lane_dest)" "NONE"

# A refused preflight (here, a base repository that configures no identity)
# pushes nothing by either path.
lane_run "$wc"
check "lane, preflight refused: exits non-zero" "$(nonzero)" "nonzero"
check "lane, preflight refused: nothing pushed" "$(lane_dest)" "NONE"

# --pr in a lane: the PR's head, from the worktree that has it checked out.
wt_l="$WORKDIR/lane/wt-b"
git -C "$wc" worktree add -q -b feat/b "$wt_l" 2>/dev/null
PB_IDENTITY="$LANE" lane_run "$wc" --pr 46
check "lane --pr: pushes the PR's head branch" "$(lane_dest)" \
  "https://github.com/example-org/app.git HEAD:refs/heads/feat/b"
check "lane --pr: pushes from the PR worktree" "$(cat "$LOG/push.cwd" 2>/dev/null)" "$(cd "$wt_l" && pwd -P)"

# --pr takes the destination from the PR, never the remote's push URL: a push
# URL naming another repository is not where the lane pushes.
git -C "$wc" remote set-url --push origin https://github.com/other-org/app.git
PB_IDENTITY="$LANE" lane_run "$wc" --pr 46
check "lane --pr, push URL elsewhere: pushes to the PR's head repository" "$(lane_dest)" \
  "https://github.com/example-org/app.git HEAD:refs/heads/feat/b"

# --dir: the HEAD of that checkout, detached included.
wt_ld="$WORKDIR/lane/wt-d"
git -C "$wc" worktree add -q --detach "$wt_ld" feat/b 2>/dev/null
PB_IDENTITY="$LANE" lane_run "$wc" --dir "$wt_ld" --pr 46
check "lane --dir: exit 0" "$RC" "0"
check "lane --dir: pushes from that checkout" "$(cat "$LOG/push.cwd" 2>/dev/null)" "$(cd "$wt_ld" && pwd -P)"
check "lane --dir: pushes the PR's head branch" "$(lane_dest)" \
  "https://github.com/example-org/app.git HEAD:refs/heads/feat/b"

# A fork PR's head name can match a local in-repo branch, so in a lane --pr
# without --dir refuses for a fork head instead of pushing that branch to the
# fork; with --dir it pushes that checkout to the fork's head.
PB_PR_HEAD_REPO=someone/fork PB_IDENTITY="$LANE" lane_run "$wc" --pr 46
check "lane --pr, fork head without --dir: exits non-zero" "$(nonzero)" "nonzero"
check "lane --pr, fork head without --dir: nothing pushed" "$(lane_dest)" "NONE"
PB_PR_HEAD_REPO=someone/fork PB_IDENTITY="$LANE" lane_run "$wc" --dir "$wt_ld" --pr 46
check "lane --dir --pr, fork head: exit 0" "$RC" "0"
check "lane --dir --pr, fork head: pushes to the fork's head" "$(lane_dest)" \
  "https://github.com/someone/fork.git HEAD:refs/heads/feat/b"

# A branch checked out in no worktree has no HEAD for lane-push.sh: refused.
wc=$(make_clone lane-idle)
git -C "$wc" remote set-url origin https://github.com/example-org/app.git
git -C "$wc" branch -q feat/idle
PB_IDENTITY="$LANE" lane_run "$wc" feat/idle
check "lane, idle branch: exits non-zero" "$(nonzero)" "nonzero"
check "lane, idle branch: nothing pushed" "$(lane_dest)" "NONE"

# An operator login keeps the operator path: the remote receives the branch
# through plain git, and neither the preflight nor lane-push.sh is involved.
wc=$(make_clone operator)
rm -f "$LOG"/*
(cd "$wc" && PB_LOGIN=operator-example bash "$PUSH_BRANCH") >/dev/null 2>&1
check "operator: the remote received the branch by plain git" "$(has_branch "$WORKDIR/operator/origin")" "yes"
check "operator: no identity preflight" "$([[ -f $LOG/preflight.argv ]] && echo ran || echo none)" "none"

# R4, the named residual: a failed acting-login read is read as an operator,
# so the push takes the operator path, by plain git to the remote.
wc=$(make_clone login-fail)
rm -f "$LOG"/*
(cd "$wc" && PB_LOGIN_FAIL=1 bash "$PUSH_BRANCH") >/dev/null 2>&1
check "login read failed: exit 0 on the operator path" "$?" "0"
check "login read failed: the remote received the branch by plain git" "$(has_branch "$WORKDIR/login-fail/origin")" "yes"
check "login read failed: no identity preflight" "$([[ -f $LOG/preflight.argv ]] && echo ran || echo none)" "none"

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
