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

fetch_config() {
  git -C "$1" config "branch.${BRANCH}.remote" 2>/dev/null || echo UNSET
}

merge_config() {
  git -C "$1" config "branch.${BRANCH}.merge" 2>/dev/null || echo UNSET
}

# 1. Fresh-branch bootstrap: no branch.remote, no push config. Fetch and push
#    both fall back to origin -> equal -> `-u` fires, tracking is bootstrapped.
wc=$(make_clone bootstrap)
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "bootstrap: -u fired, branch.remote set to origin" "$(fetch_config "$wc")" "origin"
check "bootstrap: origin received the branch" "$(has_branch "$WORKDIR/bootstrap/origin")" "yes"

# 2. Non-triangular, established upstream: branch.remote=origin already set, with
#    a NON-default merge ref (tracks origin/main). Push resolves origin too, but
#    the upstream already exists -> plain push -> the merge ref must survive. An
#    always-`-u` (or resolved-name-only) gate would rewrite it to refs/heads/feat/x.
wc=$(make_clone nontri)
git -C "$wc" config "branch.${BRANCH}.remote" origin
git -C "$wc" config "branch.${BRANCH}.merge" refs/heads/main
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "non-triangular: branch.remote stays origin" "$(fetch_config "$wc")" "origin"
check "non-triangular: merge ref preserved (not rewritten by -u)" "$(merge_config "$wc")" "refs/heads/main"
check "non-triangular: origin received the branch" "$(has_branch "$WORKDIR/nontri/origin")" "yes"

# 3. Triangular via branch.<name>.pushRemote: fetch upstream, push fork.
#    Resolved remotes differ -> plain push -> branch.remote preserved as upstream.
wc=$(make_clone tri-pushremote upstream fork)
git -C "$wc" config "branch.${BRANCH}.remote" upstream
git -C "$wc" config "branch.${BRANCH}.pushRemote" fork
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "pushRemote-tri: fetch remote preserved (upstream)" "$(fetch_config "$wc")" "upstream"
check "pushRemote-tri: fork received the branch" "$(has_branch "$WORKDIR/tri-pushremote/fork")" "yes"
check "pushRemote-tri: origin did NOT receive the branch" "$(has_branch "$WORKDIR/tri-pushremote/origin")" "no"

# 4. THE #442 REGRESSION: pushDefault-only triangular. branch.remote UNSET,
#    remote.pushDefault=fork, origin present. Fetch falls back to origin, push
#    resolves fork. Resolved remotes differ -> plain push -> branch.remote stays
#    UNSET, so the next fetch/rebase still targets origin (no silent clobber).
wc=$(make_clone tri-pushdefault fork)
git -C "$wc" config remote.pushDefault fork
(cd "$wc" && bash "$PUSH_BRANCH") >/dev/null 2>&1
check "pushDefault-tri: branch.remote NOT clobbered (stays unset)" "$(fetch_config "$wc")" "UNSET"
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
check "fetch-ambiguous: branch.remote not written" "$(fetch_config "$wc")" "UNSET"
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
check "dot-upstream: branch.remote stays '.' (local-only preserved)" "$(fetch_config "$wc")" "."
check "dot-upstream: merge ref preserved (not rewritten by -u)" "$(merge_config "$wc")" "refs/heads/main"
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
check "merge-only: branch.remote not written (stays unset)" "$(fetch_config "$wc")" "UNSET"
check "merge-only: merge ref preserved (not rewritten by -u)" "$(merge_config "$wc")" "refs/heads/main"
check "merge-only: origin received the branch" "$(has_branch "$WORKDIR/merge-only/origin")" "yes"

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
