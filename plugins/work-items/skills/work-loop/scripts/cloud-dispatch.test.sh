#!/usr/bin/env bash
# Regression tests for cloud-dispatch.sh (self-contained; ships with the plugin).
#
# Expected values come from the execution-target contract
# (docs/conventions/execution-target/README.md): the resolution order, the
# per-item cloud-session rule, the untrusted-input guard and the cloud launch
# rule. Real git (a bare origin and a clone) with PATH stubs for gh and claude;
# no network. The sandbox path holds a literal `$(...)` and every case runs
# under BASH_COMPAT=51, so a script that evaluated a path or value would create
# a PWNED file.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/cloud-dispatch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_DATA="$TMP/data"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

# --- Stubs --------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"
GH_LOG="$TMP/gh.log"
CLAUDE_LOG="$TMP/claude.log"
cat >"$BIN/gh" <<STUB
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >>"$GH_LOG"
jqf="" prev=""
for a in "\$@"; do [[ "\$prev" == "--jq" ]] && jqf="\$a"; prev="\$a"; done
case "\$*" in
*"/issues/"*"/comments"*)
  [[ "\${STUB_GH_COMMENTS_RC:-0}" != 0 ]] && exit "\$STUB_GH_COMMENTS_RC"
  jq -r "\$jqf" <<<"\${STUB_GH_COMMENTS:-[]}"
  ;;
*"user/installations/"*"/repositories"*)
  data="\${STUB_GH_REPOS:-}"
  [[ -n "\$data" ]] || data='{"repositories":[]}'
  jq -r "\$jqf" <<<"\$data"
  ;;
*"user/installations"*)
  data="\${STUB_GH_INSTALLATIONS:-}"
  [[ -n "\$data" ]] || data='{"installations":[{"id":7,"app_slug":"claude","repository_selection":"all","account":{"login":"Acme"}}]}'
  jq -r "\$jqf" <<<"\$data"
  ;;
*) exit 1 ;;
esac
STUB
cat >"$BIN/claude" <<STUB
#!/usr/bin/env bash
{ printf 'cwd %s\n' "\$PWD"; printf 'arg %s\n' "\$@"; } >>"$CLAUDE_LOG"
printf 'Session ID: session_01Fixture\nView: https://claude.ai/code/session_01Fixture?from=cli\n'
STUB
chmod +x "$BIN/gh" "$BIN/claude"
PATH="$BIN:$PATH"

# --- Fixture repositories -----------------------------------------------------
SANDBOX="$TMP/sb \$(touch PWNED) x"
mkdir -p "$SANDBOX"
ORIGIN="$SANDBOX/origin.git"
REPO="$SANDBOX/repo"
fx_git() { git -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
git init -q --bare -b main "$ORIGIN"
git clone -q "$ORIGIN" "$REPO" 2>/dev/null
mkdir -p "$REPO/docs/conventions"

publish() { # <yaml or empty>: commit it on origin's main (empty removes the file)
  if [[ -n "$1" ]]; then
    printf '%s\n' "$1" >"$REPO/docs/conventions/execution-target.yaml"
  else
    rm -f "$REPO/docs/conventions/execution-target.yaml"
  fi
  fx_git -C "$REPO" add -A
  fx_git -C "$REPO" commit -q --allow-empty -m fixture
  fx_git -C "$REPO" push -q origin HEAD:main 2>/dev/null
  git -C "$REPO" remote set-head origin main >/dev/null 2>&1
  SHA_NOW="$(git -C "$REPO" rev-parse HEAD)"
}
# origin as github.com/acme/widgets, reached through insteadOf. The shipped
# script refuses that rewrite, so the cloud cases run a copy whose rewrite
# check is off; everything else in the copy is the shipped code.
origin_github() {
  git -C "$REPO" remote set-url origin https://github.com/acme/widgets.git
  git -C "$REPO" config "url.$ORIGIN.insteadOf" https://github.com/acme/widgets.git
}
origin_local() {
  git -C "$REPO" config --unset-all "url.$ORIGIN.insteadOf" 2>/dev/null
  git -C "$REPO" remote set-url origin "$ORIGIN"
}
COPY_DIR="$TMP/copy"
mkdir -p "$COPY_DIR"
cp -R "$SCRIPT_DIR/lib" "$COPY_DIR/lib"
sed -e 's/^origin_url_rewritten() {$/origin_url_rewritten() { return 1; }\
origin_url_rewritten_shipped() {/' "$SCRIPT" >"$COPY_DIR/cloud-dispatch.sh"
assert_contains "the test copy turns off only the origin-rewrite check" "$(cat "$COPY_DIR/cloud-dispatch.sh")" 'origin_url_rewritten() { return 1; }'

run_shipped() { BASH_COMPAT=51 bash "$SCRIPT" --repo "$REPO" "$@" 2>"$TMP/err"; }
run_github() {
  local rc
  origin_github
  BASH_COMPAT=51 bash "$COPY_DIR/cloud-dispatch.sh" --repo "$REPO" "$@" 2>"$TMP/err"
  rc=$?
  origin_local
  return "$rc"
}
field() { jq -r ".$1" <<<"$2"; }

# --- Resolution ---------------------------------------------------------------
publish ""
out="$(run_shipped --item 12 --class mechanical)"
assert_eq "no policy file: the item runs locally" "local" "$(field dispatch "$out")"
assert_eq "no policy file: target is the built-in local-worktree" "local-worktree" "$(field target "$out")"
assert_contains "no policy file: the reason names the absent file" "$(field reason "$out")" "absent at origin/main"

publish $'default: local-worktree\nclass:\n  mechanical: cloud-session'
: >"$GH_LOG"
out="$(run_github --item 12 --class mechanical)"
assert_eq "class key cloud-session for a trusted class dispatches to the cloud" "cloud" "$(field dispatch "$out")"
assert_eq "the class key supplied the value" "class.mechanical" "$(field key "$out")"
assert_eq "the SHA read is origin main's head" "$SHA_NOW" "$(field sha "$out")"
assert_eq "without --launch nothing launches" "false" "$(field launched "$out")"
assert_contains "the item's comments are read for the fallback marker" "$(cat "$GH_LOG")" "repos/acme/widgets/issues/12/comments"
assert_contains "the Claude GitHub App coverage is checked" "$(cat "$GH_LOG")" "user/installations"

publish $'skill:\n  work-items:\n    work: local-worktree\nclass:\n  mechanical: cloud-session'
out="$(run_github --item 12 --class mechanical)"
assert_eq "the skill key wins over the class key" "skill.work-items.work" "$(field key "$out")"
assert_eq "skill key local-worktree keeps the local run" "local" "$(field dispatch "$out")"

publish $'class:\n  scoped: local-background'
out="$(run_github --item 12 --class scoped)"
assert_eq "local-background per item resolves to the local run" "local" "$(field dispatch "$out")"
assert_contains "local-background: the reason says only cloud-session dispatches per item" "$(field reason "$out")" "only cloud-session dispatches per item"

publish $'default: cloud-session\nclass:\n  mechanical: cloud-sesion'
out="$(run_github --item 12 --class mechanical)"
assert_eq "an unknown value does not fall through to default" "local" "$(field dispatch "$out")"
assert_eq "an unknown value resolves local-worktree" "local-worktree" "$(field target "$out")"
assert_contains "an unknown value is reported with its key" "$(field key "$out")" "class.mechanical (unknown value)"

printf 'default: cloud-session\n' >"$REPO/docs/conventions/execution-target.yaml"
publish ""
printf 'default: cloud-session\n' >"$REPO/docs/conventions/execution-target.yaml"
out="$(run_github --item 12 --class mechanical)"
assert_eq "an uncommitted working-tree edit never moves an item" "local" "$(field dispatch "$out")"
rm -f "$REPO/docs/conventions/execution-target.yaml"

# --- Untrusted input ----------------------------------------------------------
publish $'class:\n  untrusted-provenance: cloud-session'
: >"$GH_LOG"
: >"$CLAUDE_LOG"
out="$(run_github --item 12 --class untrusted-provenance --launch)"
assert_eq "an untrusted-provenance item sent to the cloud escalates" "escalate" "$(field dispatch "$out")"
assert_contains "the escalation names attend-queue" "$(field reason "$out")" "/work-items:attend-queue"
assert_eq "an escalated item launches nothing" "" "$(cat "$CLAUDE_LOG")"

publish 'default: cloud-session'
out="$(run_github --item 12 --class unclassified --launch)"
assert_eq "a class outside the trusted labels escalates too" "escalate" "$(field dispatch "$out")"

publish 'default: local-worktree'
out="$(run_github --item 12 --class untrusted-provenance)"
assert_eq "an untrusted item whose policy is local keeps today's local handling" "local" "$(field dispatch "$out")"

# --- Cloud launch rule --------------------------------------------------------
publish 'default: cloud-session'
out="$(STUB_GH_COMMENTS='[{"body":"probe\n<!-- execution-target:fallback v1 -->\nplugin missing"}]' run_github --item 12 --class mechanical)"
assert_eq "an item carrying the fallback marker runs locally" "local" "$(field dispatch "$out")"
out="$(STUB_GH_COMMENTS_RC=1 run_github --item 12 --class mechanical)"
assert_eq "unreadable item comments keep the item local" "local" "$(field dispatch "$out")"
out="$(STUB_GH_INSTALLATIONS='{"installations":[]}' run_github --item 12 --class mechanical)"
assert_eq "no Claude GitHub App installation refuses the cloud" "local" "$(field dispatch "$out")"
assert_contains "the App refusal names the check" "$(field reason "$out")" "user/installations"
out="$(STUB_GH_INSTALLATIONS='{"installations":[{"id":9,"app_slug":"claude","repository_selection":"selected","account":{"login":"acme"}}]}' \
  STUB_GH_REPOS='{"repositories":[{"full_name":"Acme/Widgets"}]}' run_github --item 12 --class mechanical)"
assert_eq "a selected-repositories installation listing the repo admits the cloud" "cloud" "$(field dispatch "$out")"
out="$(run_shipped --item 12 --class mechanical)"
assert_eq "a non-github origin refuses the cloud" "local" "$(field dispatch "$out")"
origin_github
out="$(BASH_COMPAT=51 bash "$SCRIPT" --repo "$REPO" --item 12 --class mechanical 2>/dev/null)"
origin_local
assert_eq "the shipped script refuses a policy read through an insteadOf rewrite" "local" "$(field dispatch "$out")"
assert_contains "the rewrite refusal is the reason" "$(field reason "$out")" "insteadOf"

# --- Launch -------------------------------------------------------------------
KEY="$(printf '%s' "$(cd "$REPO" && cd "$(git rev-parse --git-common-dir)" && pwd -P)" | git hash-object --stdin | cut -c1-16)"
WT="$CLAUDE_PLUGIN_DATA/cloud-dispatch/$KEY/worktree"
: >"$CLAUDE_LOG"
out="$(run_github --item 12 --class mechanical --launch --dry-run)"
err="$(cat "$TMP/err")"
assert_eq "dry run: decision is cloud" "cloud" "$(field dispatch "$out")"
assert_contains "dry run: a detached linked worktree at the fetched SHA" "$err" "worktree add --quiet --detach $(printf '%q' "$WT") $SHA_NOW"
assert_contains "dry run: claude --cloud is printed" "$err" "DRY-RUN: claude --cloud"
assert_eq "dry run: claude is not run" "" "$(cat "$CLAUDE_LOG")"

out="$(run_github --item 12 --class mechanical --launch)"
log="$(cat "$CLAUDE_LOG")"
assert_eq "launch: dispatched to the cloud" "cloud" "$(field dispatch "$out")"
assert_eq "launch: launched" "true" "$(field launched "$out")"
assert_eq "launch: the session URL is recorded" "https://claude.ai/code/session_01Fixture" "$(field session_url "$out")"
assert_contains "launch: claude runs from the linked worktree" "$log" "cwd $(cd "$WT" && pwd -P)"
assert_contains "launch: claude --cloud is the command" "$log" "arg --cloud"
assert_contains "launch: the brief runs today's /work-items:work for the item" "$log" "run /work-items:work 12 on its autonomous invocation path"
assert_contains "launch: the brief opens with the stage-start probe" "$log" "Stage-start probe (execution target cloud-session; stage work-items:work; item #12 in acme/widgets"
assert_contains "launch: the probe carries the fallback marker" "$log" "<!-- execution-target:fallback v1 -->"
assert_contains "launch: the probe repeats the untrusted-input guard" "$log" "leave it for /work-items:attend-queue"
assert_eq "launch: the worktree sits at the fetched SHA" "$SHA_NOW" "$(git -C "$WT" rev-parse HEAD)"

printf 'stray\n' >"$WT/untracked.txt"
: >"$CLAUDE_LOG"
out="$(run_github --item 12 --class mechanical --launch)"
assert_eq "a dirty dispatch worktree refuses the cloud" "local" "$(field dispatch "$out")"
assert_eq "a dirty dispatch worktree launches nothing" "" "$(cat "$CLAUDE_LOG")"
rm -f "$WT/untracked.txt"

# --- Usage --------------------------------------------------------------------
bash "$SCRIPT" --repo "$REPO" --item '12$(touch PWNED)' --class mechanical >/dev/null 2>&1
assert_eq "a non-numeric item is a usage error" "2" "$?"
bash "$SCRIPT" --repo "$REPO" --item 12 --class 'mech anical' >/dev/null 2>&1
assert_eq "a malformed class is a usage error" "2" "$?"
bash "$SCRIPT" --repo "$REPO" --item 12 >/dev/null 2>&1
assert_eq "a missing class is a usage error" "2" "$?"

assert_eq "no value or path was evaluated" "" "$(find "$TMP" "$PWD" -maxdepth 3 -name PWNED 2>/dev/null)"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
((FAILED == 0))
