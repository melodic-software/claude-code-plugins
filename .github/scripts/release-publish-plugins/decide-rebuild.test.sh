#!/usr/bin/env bash
# Tests for decide-rebuild.sh on a throwaway origin and clone, with a stub gh
# on PATH and a stub fragment gate on main whose exit code GATE_RC sets; the
# gate's own cases (scripts/check-changelog-fragments.test.sh) cover what it
# counts as current.
# Canned gh responses follow the shapes the script reads: `gh pr list --json`
# rows, GraphQL PullRequest.isInMergeQueue, and the REST check-runs list.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DECIDE="$SCRIPT_DIR/decide-rebuild.sh"

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
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

# The stub gh answers the three reads decide-rebuild.sh makes and applies
# --jq through jq, as gh does.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
jq_expr=. prev=
for a in "$@"; do
  [ "$prev" = --jq ] && jq_expr=$a
  prev=$a
done
case "$1 $2" in
'pr list') json="$FAKE_PRS" ;;
'api graphql')
  if [[ $FAKE_QUEUED == fail ]]; then exit 1; fi
  json="{\"data\":{\"node\":{\"isInMergeQueue\":$FAKE_QUEUED}}}" ;;
api\ repos/*) json="{\"check_runs\":[{\"started_at\":\"2026-10-18T01:00:00Z\",\"conclusion\":\"$FAKE_CI\"}]}" ;;
*) exit 9 ;;
esac
jq -r "$jq_expr" <<<"$json"
EOF
chmod +x "$TMP/bin/gh"

tg() { git -C "$R" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"; }
commit() { tg commit -q --allow-empty -m "$1"; }

# new_fixture <behind>: origin with main and a release branch one commit apart;
# with behind=yes main gains a commit after the release head was cut. R is the
# clone, left on main.
new_fixture() {
  local origin="$TMP/origin.$RANDOM$RANDOM"
  git init -q --bare -b main "$origin"
  R="$(mktemp -d "$TMP/clone.XXXXXX")"
  git clone -q "$origin" "$R" 2>/dev/null
  tg checkout -q -b main
  mkdir -p "$R/scripts"
  # shellcheck disable=SC2016  # the stub expands GATE_RC when it runs
  printf '#!/usr/bin/env bash\nexit "${GATE_RC:-0}"\n' >"$R/scripts/check-changelog-fragments.sh"
  chmod +x "$R/scripts/check-changelog-fragments.sh"
  tg add -A
  commit base
  tg checkout -q -b release
  commit release
  HEAD_SHA=$(tg rev-parse HEAD)
  tg checkout -q main
  if [[ $1 == yes ]]; then commit 'main moves on'; fi
  tg push -q origin main release:release/plugins-39902821663
  MAIN_SHA=$(tg rev-parse main)
}

# run_decide [env assignments...]: sets RC, OUT (stdout) and GHOUT (the
# GITHUB_OUTPUT lines).
run_decide() {
  : >"$TMP/ghout"
  : >"$TMP/gh.log"
  RC=0
  OUT=$(cd "$R" && env PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GH_TOKEN=t \
    GITHUB_REPOSITORY=o/r GITHUB_OUTPUT="$TMP/ghout" GITHUB_EVENT_NAME=schedule \
    FAKE_PRS="${FAKE_PRS-}" FAKE_QUEUED=false FAKE_CI=success "$@" \
    bash "$DECIDE" "$MAIN_SHA" 2>"$TMP/err") || RC=$?
  GHOUT=$(cat "$TMP/ghout")
}
val() { sed -n "s/^$1=//p" <<<"$GHOUT"; }
# pr_json <mergeable> [head branch]: one open same-repository pull request.
pr_json() { printf '[{"id":"PR_n","number":7,"headRefName":"%s","headRefOid":"%s","mergeable":"%s","isCrossRepository":false}]' "${2:-release/plugins-39902821663}" "$HEAD_SHA" "$1"; }

echo '# no open release pull request'
new_fixture no
FAKE_PRS='[]' run_decide
check 'none: exit 0' 0 "$RC"
check 'none: rebuild' true "$(val rebuild)"
check 'none: found=false' false "$(val found)"

echo '# the open release pull request is found by its branch pattern'
new_fixture no
other='{"id":"PR_o","number":6,"headRefName":"feat/x","headRefOid":"0","mergeable":"MERGEABLE","isCrossRepository":false}'
FAKE_PRS="[$other,$(pr_json MERGEABLE | sed 's/^\[//')" run_decide GATE_RC=0
check 'pattern: the release pull request, past another one' 'true 7 release/plugins-39902821663' "$(val found) $(val number) $(val branch)"
check 'pattern: lists every open pull request on main, not one --head' 0 "$(grep -c -- '--head' "$TMP/gh.log" || true)"
FAKE_PRS="$(pr_json MERGEABLE release/plugins)" run_decide GATE_RC=0
check 'pattern: a release still on the bare branch is reused' 'true release/plugins' "$(val found) $(val branch)"
for branch in release/plugins-next release/plugins-fork feat/release/plugins-1; do
  FAKE_PRS="$(pr_json MERGEABLE "$branch")" run_decide
  check "pattern: $branch is not the release pull request" 'false true' "$(val found) $(val rebuild)"
done
FAKE_PRS="$(pr_json MERGEABLE | sed 's/"isCrossRepository":false/"isCrossRepository":true/')" run_decide
check 'pattern: a fork on the release branch name is not the release pull request' false "$(val found)"

echo '# queued release pull request that main went stale under'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide FAKE_QUEUED=true GATE_RC=1
check 'queued: exit 0' 0 "$RC"
check 'queued: no rebuild' false "$(val rebuild)"
check 'queued: notice names the pull request' 1 "$(grep -c '^::notice::.*#7 .*merge queue' <<<"$OUT" || true)"
check 'queued: pull request outputs still written' "PR_n 7 $HEAD_SHA" "$(val id) $(val number) $(val head)"

echo '# queued release pull request with a merge conflict'
new_fixture no
FAKE_PRS="$(pr_json CONFLICTING)" run_decide FAKE_QUEUED=true
check 'queued conflict: no rebuild' false "$(val rebuild)"

echo '# queue lookup fails'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide FAKE_QUEUED=fail GATE_RC=1
check 'lookup failure: non-zero exit' 1 "$((RC != 0))"
check 'lookup failure: no rebuild written' '' "$(val rebuild)"

echo '# not queued, main changed a file it changes'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GATE_RC=1
check 'stale: exit 0' 0 "$RC"
check 'stale: rebuild' true "$(val rebuild)"
check 'stale: tree back on main' "$MAIN_SHA" "$(tg rev-parse HEAD)"

echo '# not queued, merge conflict'
new_fixture no
FAKE_PRS="$(pr_json CONFLICTING)" run_decide
check 'conflict: rebuild' true "$(val rebuild)"

echo '# not queued, current'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GATE_RC=0 FAKE_CI=failure
check 'current: exit 0' 0 "$RC"
check 'current: no rebuild (a failure on a current base is not rebuilt)' false "$(val rebuild)"

echo '# not queued, base behind main, ci-status failed'
new_fixture yes
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GATE_RC=0 FAKE_CI=failure
check 'behind+failed: rebuild' true "$(val rebuild)"

echo '# not queued, base behind main, ci-status passed'
new_fixture yes
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GATE_RC=0 FAKE_CI=success
check 'behind+passed: no rebuild' false "$(val rebuild)"

echo '# gate error'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GATE_RC=2
check 'gate error: exit 2' 2 "$RC"
check 'gate error: no rebuild written' '' "$(val rebuild)"

echo '# push: no open release pull request'
new_fixture no
FAKE_PRS='[]' run_decide GITHUB_EVENT_NAME=push
check 'push none: exit 0' 0 "$RC"
check 'push none: builds one (no checks to cancel)' 'true ' "$(val rebuild) $(val deferred)"

echo '# push: main changed a file it changes'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GITHUB_EVENT_NAME=push GATE_RC=1
check 'push stale: exit 0' 0 "$RC"
check 'push stale: no rebuild, deferred' 'false true' "$(val rebuild) $(val deferred)"
check 'push stale: tree back on main' "$MAIN_SHA" "$(tg rev-parse HEAD)"

echo '# push: merge conflict'
new_fixture no
FAKE_PRS="$(pr_json CONFLICTING)" run_decide GITHUB_EVENT_NAME=push
check 'push conflict: no rebuild, deferred' 'false true' "$(val rebuild) $(val deferred)"

echo '# push: base behind main, ci-status failed'
new_fixture yes
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GITHUB_EVENT_NAME=push GATE_RC=0 FAKE_CI=failure
check 'push behind+failed: no rebuild, deferred' 'false true' "$(val rebuild) $(val deferred)"

echo '# push: current'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GITHUB_EVENT_NAME=push GATE_RC=0
check 'push current: no rebuild, not deferred' 'false ' "$(val rebuild) $(val deferred)"

echo '# workflow_dispatch: main changed a file it changes'
new_fixture no
FAKE_PRS="$(pr_json MERGEABLE)" run_decide GITHUB_EVENT_NAME=workflow_dispatch GATE_RC=1
check 'dispatch stale: rebuild' true "$(val rebuild)"

exit "$FAILED"
