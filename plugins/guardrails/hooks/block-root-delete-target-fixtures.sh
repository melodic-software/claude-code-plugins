#!/usr/bin/env bash
# Each part sources this file, so the parts use what it defines.
# shellcheck disable=SC2016,SC1003,SC2034,SC2329

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/block-root-delete-target.sh"
GUARD_UNDER_TEST="$HOOK"

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"
unset CLAUDE_CODE_SESSION_ATTENDED GUARDRAILS_SESSION_UNWATCHED
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
  rdt_ar() {
    local -a env=("HOME=${5:-$RDT_AH}")
    [[ -z "${4:-}" ]] || env+=("$RDT_KEY=$4")
    expect_both "allowed roots: $1" "$2" --cwd / --command "$3" -- "${env[@]}"
  }
}

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

rdt_finish() {
  echo "host-conditional groups skipped: $rdt_skips"
  report
}
