# shellcheck shell=bash

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

unset CLAUDE_PLUGIN_DATA HOOK_TELEMETRY_SINK

# A native jq.exe under MSYS2 or Cygwin writes CRLF unless given --binary:
# https://jqlang.org/manual/
jq_crlf_free() {
  [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == win32* ]] || return 0
  # shellcheck disable=SC2329  # invoked by the suite that called jq_crlf_free
  jq() { command jq --binary "$@"; }
}

: "${PASS:=0}"
: "${FAIL:=0}"

ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
bad() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

assert_eq() {
  if [[ "$3" == "$2" ]]; then ok "$1 ($3)"; else bad "$1: expected '$2', got '$3'"; fi
}
assert_exit() {
  if [[ "$3" == "$2" ]]; then ok "$1 (exit $3)"; else bad "$1: expected exit $2, got $3"; fi
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1: '$3' not in output: $2"; fi
}
assert_absent() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1: unexpected '$3' in output"; fi
}
assert_silent() {
  if [[ -z "$2" ]]; then ok "$1"; else bad "$1: expected empty output, got: $2"; fi
}
assert_file_absent() {
  if [[ ! -e "$2" ]]; then ok "$1"; else bad "$1: file exists: $2"; fi
}

# shellcheck disable=SC2016  # the sed script and the needle are literal hook source text
assert_file_dir_seam() {
  local seam fp FILE FILE_DIR
  seam=$(sed -n '/^FILE_DIR="\${FILE%\/\*}"$/,/^REPO_ROOT=/{/^REPO_ROOT=/d;p}' "$1")
  assert_contains "file-dir seam: lifted from the hook" "$seam" 'FILE_DIR="${FILE%/*}"'
  for fp in /bar.md bar.md /a/b/bar.md; do
    # shellcheck disable=SC2034  # read by the eval below
    FILE="$fp"
    FILE_DIR=""
    eval "$seam"
    assert_eq "file-dir seam: $fp anchors where dirname does" "$(dirname "$fp")" "$FILE_DIR"
  done
}

write_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg c "$2" \
    '{tool_name:"Write",tool_input:{file_path:$fp,content:$c}}'
}
edit_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg s "$2" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,new_string:$s}}'
}
# Claude Code's NotebookEdit input names its target notebook_path, never file_path:
# https://code.claude.com/docs/en/agent-sdk/python
notebook_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg np "$1" --arg s "$2" \
    '{tool_name:"NotebookEdit",tool_input:{notebook_path:$np,new_source:$s}}'
}
other_tool_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg t "$1" --arg fp "$2" \
    '{tool_name:$t,tool_input:{file_path:$fp}}'
}
command_json() {
  jq -n --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}'
}
pwsh_command_json() {
  jq -n --arg cmd "$1" '{tool_name:"PowerShell",tool_input:{command:$cmd}}'
}
replall_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg fp "$1" --arg s "$2" \
    '{tool_name:"Edit",tool_input:{file_path:$fp,new_string:$s,replace_all:true}}'
}
nul_payload() {
  jq -n --arg h "$1" --arg t "$2" \
    '{tool_name:"Bash",tool_input:{command:($h + ([0] | implode) + $t)}}'
}
size_filler() { head -c "$1" /dev/zero | tr '\0' b; }
sized_write_json() {
  local n="$1" tail="${2:-}"
  [[ -n "$tail" ]] && tail=" $tail"
  # shellcheck disable=SC2154  # FIXTURE is a caller contract (set by each test file)
  printf '%s%s' "$(size_filler $((n - ${#tail})))" "$tail" |
    MSYS_NO_PATHCONV=1 jq -Rs --arg fp "$FIXTURE" \
      '{tool_name:"Write",tool_input:{file_path:$fp,content:.}}'
}
mcp_single_json() {
  jq -n --arg p "$1" --arg c "$2" \
    '{tool_name:"mcp__github__create_or_update_file",tool_input:{owner:"o",repo:"r",branch:"main",message:"m",path:$p,content:$c}}'
}
mcp_push_json() {
  local jq_args=() n=0
  while (($#)); do
    jq_args+=(--arg "p$n" "$1" --arg "c$n" "$2")
    shift 2
    n=$((n + 1))
  done
  local filter='{tool_name:"mcp__github__push_files",tool_input:{owner:"o",repo:"r",branch:"main",message:"m",files:['
  local i
  for ((i = 0; i < n; i++)); do
    ((i)) && filter+=','
    # shellcheck disable=SC2016  # $p<i>/$c<i> are jq --arg variables, not shell expansions
    filter+='{path:$p'"$i"',content:$c'"$i"'}'
  done
  filter+=']}}'
  jq -n "${jq_args[@]}" "$filter"
}
scoped() { jq --arg t "mcp__plugin_github_github__$1" '.tool_name = $t'; }
alias_chain() {
  local n="$1" terminal="$2" mode="${3:-same}" cmd="git" i
  for ((i = 1; i < n; i++)); do
    if [[ "$mode" == diverge ]]; then
      cmd+=" -c alias.a$i='a$((i + 1)) --x$i' -c alias.a$i.command='a$((i + 1)) --y$i'"
    else
      cmd+=" -c alias.a$i=a$((i + 1)) -c alias.a$i.command=a$((i + 1))"
    fi
  done
  printf '%s' "$cmd -c alias.a$n='$terminal' -c alias.a$n.command='$terminal' a1"
}

GUARDRAILS_HOOK_DIR="${BASH_SOURCE[0]%/*}"
: "${GUARD_DISPATCH:=$GUARDRAILS_HOOK_DIR/run-guards.sh}"
: "${GUARD_VIA:=direct}"
GUARD_OUT=""
GUARD_ERR=""
GUARD_RC=0

# shellcheck disable=SC2034  # GUARD_OUT/GUARD_ERR are read by the sourcing suite
guard_invoke() {
  local _gi_via="$GUARD_VIA" _gi_hook="${GUARD_UNDER_TEST:-}" _gi_tool=Bash
  local _gi_command="" _gi_cwd="" _gi_payload="" _gi_have_payload=0
  local _gi_chdir="" _gi_merge=0
  local -a _gi_envs=() _gi_also=() _gi_libs=()
  while (($#)); do
    case "$1" in
    --tool)
      _gi_tool="$2"
      shift 2
      ;;
    --command)
      _gi_command="$2"
      shift 2
      ;;
    --cwd)
      _gi_cwd="$2"
      shift 2
      ;;
    --payload)
      _gi_payload="$2"
      _gi_have_payload=1
      shift 2
      ;;
    --hook)
      _gi_hook="$2"
      shift 2
      ;;
    --also)
      _gi_also+=("$2")
      shift 2
      ;;
    --lib)
      _gi_libs+=(--lib "$2")
      shift 2
      ;;
    --via)
      _gi_via="$2"
      shift 2
      ;;
    --chdir)
      _gi_chdir="$2"
      shift 2
      ;;
    --merge-stderr)
      _gi_merge=1
      shift
      ;;
    --)
      shift
      _gi_envs=("$@")
      break
      ;;
    *)
      bad "guard_invoke: unknown option '$1'"
      GUARD_RC=64
      return 64
      ;;
    esac
  done
  if ((_gi_have_payload == 0)); then
    _gi_payload=$(MSYS_NO_PATHCONV=1 jq -n \
      --arg t "$_gi_tool" --arg c "$_gi_command" --arg d "$_gi_cwd" \
      '{tool_name:$t,tool_input:{command:$c}} + (if $d == "" then {} else {cwd:$d} end)')
  fi
  local -a _gi_argv=()
  if ((${#_gi_envs[@]})); then _gi_argv=(env "${_gi_envs[@]}"); fi
  case "$_gi_via" in
  direct) _gi_argv+=(bash "$_gi_hook") ;;
  dispatched)
    _gi_argv+=(bash "$GUARD_DISPATCH" ${_gi_libs[@]+"${_gi_libs[@]}"} "$_gi_hook"
      ${_gi_also[@]+"${_gi_also[@]}"})
    ;;
  *)
    bad "guard_invoke: unknown --via '$_gi_via'"
    GUARD_RC=64
    return 64
    ;;
  esac
  local _gi_errf="${TEST_TMPDIR:?guard_invoke needs TEST_TMPDIR}/guard-invoke.err"
  GUARD_RC=0
  GUARD_ERR=""
  if ((_gi_merge)); then
    GUARD_OUT=$(cd "${_gi_chdir:-.}" && "${_gi_argv[@]}" <<<"$_gi_payload" 2>&1) || GUARD_RC=$?
  else
    GUARD_OUT=$(cd "${_gi_chdir:-.}" && "${_gi_argv[@]}" <<<"$_gi_payload" 2>"$_gi_errf") || GUARD_RC=$?
    GUARD_ERR=$(<"$_gi_errf")
  fi
  return "$GUARD_RC"
}

expect() {
  local label="$1" expected="$2"
  shift 2
  guard_invoke "$@"
  assert_exit "$label" "$expected" "$GUARD_RC"
}

expect_both() {
  local label="$1" expected="$2"
  shift 2
  expect "$label (direct)" "$expected" --via direct "$@"
  expect "$label (dispatched)" "$expected" --via dispatched "$@"
}

nul_stderr() {
  guard_invoke --payload "$(nul_payload "$1" "$2")"
  printf '%s' "$GUARD_ERR"
  return "$GUARD_RC"
}

assert_bounded_exit() {
  if [[ "$3" == "124" ]]; then
    bad "$1: HUNG (exit 124 at the 150s bound) — here-string deadlock regression"
  elif [[ "$3" == "$2" ]]; then
    ok "$1 (exit $3)"
  else
    bad "$1: expected exit $2, got $3"
  fi
}

run_payload() {
  # shellcheck disable=SC2154  # HOOK/REPO are a caller contract (set by each test file)
  guard_invoke --hook "${HOOK_OVERRIDE:-$HOOK}" --merge-stderr --payload "$1" \
    -- "CLAUDE_PROJECT_DIR=$REPO"
  # shellcheck disable=SC2034  # OUT is read by the sourcing suite
  OUT="$GUARD_OUT"
  return "$GUARD_RC"
}
# shellcheck disable=SC2154  # TARGET is a caller contract (set by each test file)
run() { run_payload "$(write_json "$TARGET" "$1")"; }
# run_edit <new_string> -> same, as an Edit payload.
# shellcheck disable=SC2154  # TARGET is a caller contract (set by each test file)
run_edit() { run_payload "$(edit_json "$TARGET" "$1")"; }

assert_run_helpers_propagate_exit() {
  local stub="${TEST_TMPDIR:?assert_run_helpers_propagate_exit needs TEST_TMPDIR}/rc-stub-hook.sh"
  # shellcheck disable=SC2034  # read by run_payload through dynamic scope
  local HOOK_OVERRIDE="$stub"
  printf '#!/usr/bin/env bash\nexit 3\n' >"$stub"
  run 'anything'
  assert_exit "run propagates a nonzero hook exit" 3 "$?"
  run_edit 'anything'
  assert_exit "run_edit propagates a nonzero hook exit" 3 "$?"
}

parity() {
  local label="$1" content="$2" expected="$3" needle="$4" payload via
  payload="$(write_json "$TARGET" "$content")"
  for via in direct dispatched; do
    guard_invoke --via "$via" --merge-stderr --payload "$payload" \
      -- "CLAUDE_PROJECT_DIR=$REPO"
    assert_exit "$label ($via)" "$expected" "$GUARD_RC"
    if [[ -n "$needle" ]]; then
      assert_contains "$label ($via): finding survives" "$GUARD_OUT" "$needle"
    else
      assert_silent "$label ($via): stays quiet" "$GUARD_OUT"
    fi
  done
}

make_sink() {
  local s
  # shellcheck disable=SC2154  # TEST_TMPDIR is a caller contract (set by each test file)
  s="$(mktemp "$TEST_TMPDIR/sink.XXXXXX")"
  printf '#!/usr/bin/env bash\n%s\n' "$1" >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

report() {
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
}
