#!/usr/bin/env bash
# PreToolUse hook: block `git commit` that does not feed its message via stdin.
# Triggered on Bash tool calls.
#
# WHAT IT ENFORCES — the mechanic, not the ritual:
#   `git commit -F -` (or `--file -`), the form the /commit skill emits. The
#   failure mode it prevents is real and silent: `git commit -m "<multi-line>"`
#   flattens newlines unpredictably across shells, so a body that looked right
#   in the tool call lands mangled in history.
#
# WHY NOT `--trailer`: the trailer is POLICY, not mechanic. /commit itself
# omits it when the resolved trailer_policy is `none`, and a repo whose
# convention forbids a co-author trailer is a documented, supported case.
# Gating on it would permanently block the skill's own canonical output in that
# configuration. Only the stdin form belongs in a gate.
#
# WHY NOT "did you type /commit": a hook cannot tell a skill-driven Bash call
# from an ad hoc one — the payload carries no originating-skill field, and the
# upstream request to add one was declined. Gating on command SHAPE is what is
# actually available, and is the better target anyway: it enforces the outcome
# a reviewer can verify in `git log`, not the ceremony that produced it.
#
# NOT BLOCKED (no message-on-stdin form exists for these, and gating them would
# break conflict resolution and history rewriting):
#   --amend / --no-edit          reusing an existing message
#   -C / --reuse-message         "
#   -c / --reedit-message        "
#   --fixup / --squash           message derived from another commit
#   -F <path> / --file <path>    mechanic satisfied, just not via stdin
#   -m during an in-progress sequencer (merge / rebase / cherry-pick / revert):
#                                conflict resolution and rebase continuation
#                                must never be gated
#
# Per-repo/per-user allow-list: the `block_noncanonical_commit_allow` userConfig
# option is a comma-separated list of form tokens (currently just
# "message-flag", which allows a bare `-m`). Set it with
# `/plugin configure guardrails` or headless via `claude plugin install
# --config`; read from the CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW
# process mirror. Kill switch: `block_noncanonical_commit_enabled` set to false.
#
# Detection is ARGV-GRAMMAR-FAITHFUL via the shared parser in hook-utils.sh, so
# a commit body merely MENTIONING `git commit -m` never fires, and `bash -lc`
# wrappers plus git aliases are resolved. Static matching over the literal
# command string only: shell variable / command substitution is not evaluated.
#
# BLOCKING: exits 2 when a commit would take its message off the command line.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_NONCANONICAL_COMMIT"

# High-res start stamp for the telemetry envelope. EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty and skip telemetry (the block
# still fires). Referencing it bare under `set -u` would abort before exit.
start=${EPOCHREALTIME:-}

# jq is required to parse the tool payload. Fail OPEN when it is absent, but
# make the degraded state visible rather than silently disabling the guard.
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/block-noncanonical-commit: jq not found on PATH — guard disabled (install jq to enable)." >&2
  exit 0
fi

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read. rc 1
# (empty stdin) skips; rc 2 (read timed out before a complete payload) FAILS
# CLOSED — the guard cannot evaluate the tool call, and a silent skip would pass
# exactly the traffic this guard exists to stop.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | tr -d '\r')
[[ -n "$COMMAND" ]] || exit 0
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')

SUBJECT=$(hook::extract_bash_subject "Bash" "$COMMAND")

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:"Bash",subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"Bash","subject":"","form":""}'
  hook::emit_telemetry "block-noncanonical-commit" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is a form token in the block_noncanonical_commit_allow userConfig comma list?
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
allowed() {
  local tok="$1" list=",${CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW:-},"
  [[ "$list" == *,"$tok",* ]]
}

# Is a merge / rebase / cherry-pick / revert in progress? Those commits carry a
# prepared message git supplies, and `git commit` there is the documented way to
# conclude the operation — gating it would strand a conflict resolution
# mid-flight. Unknown git state answers "no": this is the permissive branch, so
# an uncertain answer must not silently open the gate.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sequencer_in_progress() {
  local dir f
  # --absolute-git-dir, not --git-dir: the latter answers relative to the repo,
  # which would resolve against the HOOK's cwd here and silently miss every
  # sequencer file.
  dir=$(git -C "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  [[ -n "$dir" ]] || return 1
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ -e "$dir/$f" ]] && return 0
  done
  return 1
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local gi sub sub_idx nseg k word next stdin_form=0 exempt=0 saw_commit=0

  # A shell -c wrapper (`bash -lc 'git commit -m x'`) executes its operand as a
  # full shell command — re-parse it with the same tokenizer.
  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_resolve_index "$@" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX

  # An inline alias runs its expansion (`git -c alias.c=commit c -m x` commits),
  # so re-check the expanded command BEFORE concluding the subcommand is not
  # `commit` — otherwise the alias name is simply not "commit" and the guard
  # waves it through. A shell alias (leading !) re-parses as a full shell
  # command; a git alias splices its words in place of the alias name. One level
  # only — git does not expand the first word of an expansion as another alias —
  # enforced through HOOK_NO_ALIAS, which dynamic scoping carries into the
  # recursive call.
  if ((${HOOK_NO_ALIAS:-0} == 0)); then
    local cv exp reparse a
    local -a cfgv=() expw=()
    cfgv=(${HOOK_GIT_CONFIG_VALUES[@]+"${HOOK_GIT_CONFIG_VALUES[@]}"})
    for cv in ${cfgv[@]+"${cfgv[@]}"}; do
      [[ "$cv" == "alias.${sub}="* ]] || continue
      exp="${cv#*=}"
      if [[ "$exp" == '!'* ]]; then
        reparse="${exp#!}"
        for a in "${w[@]:sub_idx+1}"; do reparse+=" $(printf '%q' "$a")"; done
        hook::bash_parse_segments "$reparse" check_segment
      else
        hook::env_s_split "$exp"
        expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
        HOOK_NO_ALIAS=1
        check_segment "${w[@]:0:gi+1}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}"
        HOOK_NO_ALIAS=0
      fi
      break
    done
  fi

  [[ "$sub" == "commit" ]] || return 0
  saw_commit=1

  # Scan only the words AFTER the subcommand: a top-level `git -c foo=bar` is
  # config, while `-c` after `commit` is --reedit-message.
  for ((k = sub_idx + 1; k < nseg; k++)); do
    word="${w[k]}"
    next=""
    ((k + 1 < nseg)) && next="${w[k + 1]}"
    case "$word" in
    --)
      break
      ;;
    -F | --file)
      if [[ "$next" == "-" ]]; then stdin_form=1; else exempt=1; fi
      ((k++))
      ;;
    -F- | --file=-)
      stdin_form=1
      ;;
    --file=*)
      exempt=1
      ;;
    -F*)
      exempt=1
      ;;
    --amend | --no-edit | --fixup | --squash | -C | -c | --reuse-message | --reedit-message)
      exempt=1
      ;;
    --fixup=* | --squash=* | --reuse-message=* | --reedit-message=*)
      exempt=1
      ;;
    -C* | -c*)
      exempt=1
      ;;
    *)
      # Any other word (paths, -a, -S, --cleanup, the -m payload) is not a
      # message-source marker and needs no handling here.
      ;;
    esac
  done

  ((saw_commit)) || return 0
  ((stdin_form || exempt)) && return 0
  allowed "message-flag" && return 0
  sequencer_in_progress && return 0

  echo "BLOCKED: \`git commit\` without \`-F -\` — the message must be piped via stdin." >&2
  echo "Use the /commit skill (source-control plugin), or its canonical form directly:" >&2
  echo "  git commit -F - --cleanup=verbatim <<'EOF'" >&2
  echo "  <subject>" >&2
  echo "  EOF" >&2
  echo "A \`-m\` message flattens newlines unpredictably across shells. --amend, -C/-c," >&2
  echo "--fixup/--squash, -F <path>, and an in-progress merge/rebase are exempt." >&2
  emit_tel "blocked" "message-flag"
  exit 2
}

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
