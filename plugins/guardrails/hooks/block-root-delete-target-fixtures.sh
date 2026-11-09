#!/usr/bin/env bash
# Shared fixtures for the block-root-delete-target suite, which runs in parts:
# block-root-delete-target.test.sh and block-root-delete-target-<b..>.test.sh.
# Each part sources this file, so it holds definitions and silent setup only;
# every assertion stays in the one part that runs it. A part makes TEST_TMPDIR
# and its EXIT trap before sourcing this file.
# shellcheck disable=SC2016,SC1003,SC2034,SC2329

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-root-delete-target.sh"
GUARD_UNDER_TEST="$HOOK"

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
# An interactive session exports CLAUDE_CODE_SESSION_ATTENDED=1, which turns a
# refusal into an ask (refuse.sh). Every case below asserts the deny unless it
# sets the flag itself.
unset CLAUDE_CODE_SESSION_ATTENDED GUARDRAILS_SESSION_UNWATCHED
# The worktree fixtures write git files; an inherited GIT_DIR must not redirect them.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

rdt_rep() {
  local s="" k
  for ((k = 0; k < $2; k++)); do s+="$1"; done
  printf '%s' "$s"
}

rdt_skips=0
rdt_skip() {
  echo "skip: $*"
  rdt_skips=$((rdt_skips + 1))
}

RDT_TOP=$(git -C "$HOOK_DIR" rev-parse --show-toplevel 2>/dev/null)
RDT_TOP="${RDT_TOP//$'\r'/}"

RDT_CWD=(--cwd "$RDT_TOP")

# rdt_pl <command> <cwd> [scratchpad_dir]: a payload with the harness's
# optional fields. MSYS_NO_PATHCONV keeps Git Bash from rewriting an argument
# shaped like a POSIX path (`/x`, `NAME=/x`) for a native jq.
rdt_pl() {
  if (($# > 2)); then
    MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" --arg s "$3" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d,scratchpad_dir:$s}'
  else
    MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}'
  fi
}

RDT_SPT="$TEST_TMPDIR/rdt-scratch"

rdt_br=$(rdt_rep '{' 3000)

rdt_arp() { # <label> <want> <command> [roots]
  local -a env=("HOME=$RDT_AH")
  [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
  expect_both "allowed roots: PS $1" "$2" --tool PowerShell --cwd / --command "$3" -- "${env[@]}"
}

rdt_pspl() { # <command>: a PowerShell payload from the checkout with this session's scratchpad
  MSYS_NO_PATHCONV=1 jq -n --arg c "$1" --arg d "$RDT_TOP" --arg s "$RDT_SPT" \
    '{tool_name:"PowerShell",tool_input:{command:$c},cwd:$d,scratchpad_dir:$s}'
}

# The allowed-roots tree under the checkout's .work (section 2d of the first part
# that holds it); a later part calls it first.
rdt_allowed_roots_fixture() {
  mkdir -p "$RDT_TOP/.work"
  RDT_AB=$(mktemp -d "$RDT_TOP/.work/rdt-allowed-roots.XXXXXX")
  RDT_AR="$RDT_AB/root"
  RDT_AR2="$RDT_AB/root2"
  RDT_AL="$RDT_AB/linkroot"
  RDT_AO="$RDT_AB/elsewhere"
  RDT_AH="$RDT_AB/home"
  mkdir -p "$RDT_AR/child" "$RDT_AR2/child" "$RDT_AL/child" "$RDT_AO/x" "$RDT_AH" "$RDT_AB/root-x/child"
  RDT_KEY=CLAUDE_PLUGIN_OPTION_BLOCK_ROOT_DELETE_TARGET_ALLOWED_ROOTS
  # rdt_ar <label> <want> <command> [roots [home]]: the command from `/`, HOME a
  # fake directory, the key set to <roots> when one is given.
  rdt_ar() {
    local -a env=("HOME=${5:-$RDT_AH}")
    [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
    expect_both "allowed roots: $1" "$2" --cwd / --command "$3" -- "${env[@]}"
  }
}

# The hand-built worktree registry and its stub git (section 2e); a later part
# calls it first.
rdt_worktree_fixture() {
  RDT_WF="$TEST_TMPDIR/rdt-wt"
  RDT_WR="$RDT_WF/main/.git/worktrees"
  mkdir -p "$RDT_WR/wt1" "$RDT_WR/nogit" "$RDT_WR/wt2" "$RDT_WR/.tmp-7" "$RDT_WR/wt3" \
    "$RDT_WF/wt1/build" "$RDT_WF/wt-nogit" "$RDT_WF/rel/wt2" "$RDT_WF/.tmp-7" "$RDT_WF/holder/wt3" "$RDT_WF/other"
  printf '%s\n' "$RDT_WF/wt1/.git" >"$RDT_WR/wt1/gitdir"
  printf '../..\n' >"$RDT_WR/wt1/commondir"
  printf 'gitdir: %s\n' "$RDT_WR/wt1" >"$RDT_WF/wt1/.git"
  printf '%s\n' "$RDT_WF/wt-nogit/.git" >"$RDT_WR/nogit/gitdir"
  printf '../../../../rel/wt2/.git\n' >"$RDT_WR/wt2/gitdir"
  printf '%s\n' "$RDT_WF/.tmp-7/.git" >"$RDT_WR/.tmp-7/gitdir"
  printf '%s\n' "$RDT_WF/holder/wt3/.git" >"$RDT_WR/wt3/gitdir"
  mkdir -p "$TEST_TMPDIR/bin-git-top"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$RDT_STUB_TOP"\n' >"$TEST_TMPDIR/bin-git-top/git"
  chmod +x "$TEST_TMPDIR/bin-git-top/git"
  rdt_wt() { # <label> <want> <command> [toplevel]: run from that worktree, which the stub answers
    local top="${4:-$RDT_WF/main}"
    expect_both "protected: worktrees: $1" "$2" --cwd "$top" --command "$3" \
      -- "PATH=$TEST_TMPDIR/bin-git-top:$PATH" "RDT_STUB_TOP=$top"
  }
}

# The end of every part: the host-skipped groups, then the PASS/FAIL report.
rdt_finish() {
  echo "host-conditional groups skipped: $rdt_skips"
  report
}
