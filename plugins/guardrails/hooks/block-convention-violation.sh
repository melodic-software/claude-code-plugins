#!/usr/bin/env bash
# PreToolUse hook: block a commit SUBJECT or `gh pr create --title` that
# violates the team-tracked convention pattern. Triggered on Bash and
# PowerShell tool calls.
#
# WHAT IT ENFORCES — the declarative convention, where one is explicitly
# tracked: the commit subject (first line of the canonical stdin-form message)
# and the `gh pr create --title` value are validated against the POSIX-ERE
# pattern resolved from the consumer's tracked `.claude/source-control.md` by
# the vendored enforcement resolver (resolve-convention-pattern.sh — the
# commit-convention seam, docs/conventions/commit-convention/). The sibling
# block-noncanonical-commit gate enforces the message MECHANIC (`-F -`); this
# gate reads the CONTENT that mechanic carries.
#
# UNRESOLVED = NO ENFORCEMENT. No team-tracked pattern, a non-ERE pattern, or
# an unreadable config -> the gate no-ops. It never blocks against the bundled
# Conventional Commits default: enforcement strength equals the strength of
# explicit team config, so a repo that never opted in is never gated.
#
# NEVER BLOCKS `gh pr create` ITSELF. Only a present-and-violating `--title`
# value blocks; a missing `--title` (interactive/web flow) passes untouched —
# the documented inline fallback when skill discovery is unavailable stays
# usable. PROCESS conventions (rebase, triage, body template) have no command
# signature and remain advisory (flag-commit-pr-skill-bypass).
#
# EXEMPTION TAXONOMY — inherited from block-noncanonical-commit, or this gate
# breaks conflict resolution and history rewriting: --amend, -C/--reuse-message,
# -c/--reedit-message, --fixup/--squash, -F <path>/--file <path> (message not
# on the command line; the file may not even exist yet), and any commit during
# an in-progress merge/rebase/cherry-pick/revert sequencer.
#
# DECLARED BYPASS COVERAGE (out of scope, documented): `gh pr edit --title`,
# `gh pr create --fill`, direct API calls (`gh api .../pulls`), and babysit
# retitles are not gated. A subject supplied by a non-heredoc stdin producer
# (`printf … | git commit -F -`) is not extracted — the canonical /commit form
# is the heredoc, and the mechanic gate already channels traffic into it.
#
# Kill switch: block_convention_gate_enabled userConfig option.
#
# BLOCKING: exits 2 when an extractable subject/title violates the resolved
# pattern. Extraction failure on an exempt-free stdin-form commit is a SKIP,
# not a block — the mechanic gate owns form; this gate only judges content it
# can actually read.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BLOCK_CONVENTION_GATE"

# Bundled PowerShell-command classifier — this gate is matched on both the Bash
# and the (opt-in) PowerShell tool, same as the sibling git guards. Resolved
# under the plugin root (CC sets CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback
# keeps the contract tests working when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/powershell/ps-command.sh
source "$PLUGIN_ROOT/lib/powershell/ps-command.sh"

start=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq "PreToolUse" "guardrails-block-convention-violation" "$INPUT"

hook::jq_fields "$INPUT" '.tool_name // "Bash"' '.cwd // ""' '.tool_input.command // ""'
TOOL_NAME=${HOOK_JQ_FIELDS[0]}
HOOK_CWD=${HOOK_JQ_FIELDS[1]}
COMMAND=${HOOK_JQ_FIELDS[2]}
[[ -n "$COMMAND" ]] || exit 0

REPO_ROOT=$(hook::repo_root "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}")
RESOLVER="$(dirname "${BASH_SOURCE[0]}")/resolve-convention-pattern.sh"

SUBJECT_ERE=""
TITLE_ERE=""
if [[ -f "$RESOLVER" ]]; then
  SUBJECT_ERE=$(bash "$RESOLVER" "$REPO_ROOT" subject_pattern 2>/dev/null) || SUBJECT_ERE=""
  TITLE_ERE=$(bash "$RESOLVER" "$REPO_ROOT" pr_title_pattern 2>/dev/null) || TITLE_ERE=""
fi
# Neither key enforceable -> nothing this gate could ever block.
[[ -n "$SUBJECT_ERE" || -n "$TITLE_ERE" ]] || exit 0

SUBJECT=$(hook::extract_bash_subject "$TOOL_NAME" "$COMMAND")

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg tool "$TOOL_NAME" --arg subject "$SUBJECT" --arg form "$2" \
    '{tool:$tool,subject:$subject,form:$form}' 2>/dev/null) || data='{"tool":"","subject":"","form":""}'
  hook::emit_telemetry "block-convention-violation" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# First non-empty line of the FIRST heredoc body in the raw Bash command.
# Empty output when no heredoc exists. The canonical /commit form carries
# exactly one heredoc; a command with several is judged by its first, which is
# the one `git commit -F -` reads in the canonical composition.
# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
first_heredoc_subject() {
  local cmd="$1" line delim="" in_hd=0 trimmed
  # POSIX ERE (no backreferences in [[ =~ ]]): capture the raw delimiter word,
  # then trim its quoting — the same shape flag-commit-pr-skill-bypass's
  # stripper uses.
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hd)); then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ "$trimmed" == "$delim" ]] && return 0
      # Blank-detection uses the trimmed copy, but the subject git receives is
      # the RAW line (CR aside) — leading/trailing spaces are part of what a
      # `--cleanup=verbatim` commit records, so validate exactly that.
      [[ -n "$trimmed" ]] && {
        printf '%s' "${line%$'\r'}"
        return 0
      }
      continue
    fi
    if [[ "$line" =~ $start_re ]]; then
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      in_hd=1
    fi
  done <<<"$cmd"
  return 0
}

# First non-empty line of the FIRST PowerShell here-string body (@'…'@ / @"…"@).
# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
first_herestring_subject() {
  local cmd="$1" line in_hs=0 hs_quote="" closer trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hs)); then
      closer="${hs_quote}@"
      [[ "${line:0:2}" == "$closer" ]] && return 0
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      # Blank-detection uses the trimmed copy; the subject is the RAW line
      # (CR aside) — a here-string body preserves leading/trailing spaces.
      [[ -n "$trimmed" ]] && {
        printf '%s' "${line%$'\r'}"
        return 0
      }
      continue
    fi
    if [[ "$line" == *"@'" || "$line" == *'@"' ]]; then
      hs_quote="${line: -1}"
      in_hs=1
    fi
  done <<<"$cmd"
  return 0
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
block_subject() {
  echo "BLOCKED: commit subject violates the team convention." >&2
  echo "  subject: $1" >&2
  echo "  pattern: $SUBJECT_ERE   (from .claude/source-control.md, team layer)" >&2
  echo "Rewrite the subject to match, or use the /commit skill (source-control plugin)," >&2
  echo "which drafts against the resolved convention." >&2
  emit_tel "blocked" "subject-pattern"
  exit 2
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
block_title() {
  echo "BLOCKED: PR title violates the team convention." >&2
  echo "  title:   $1" >&2
  echo "  pattern: $TITLE_ERE   (from .claude/source-control.md, team layer)" >&2
  echo "Retitle to match, or use /pull-request create (source-control plugin)." >&2
  emit_tel "blocked" "pr-title-pattern"
  exit 2
}

# Same repo-dir/sequencer helpers as block-noncanonical-commit — an in-progress
# sequencer commit carries a prepared message and is never content-gated.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
effective_dir() {
  local base="${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" i n=$# arg
  local -a a=("$@")
  for ((i = 0; i < n; i++)); do
    arg="${a[i]}"
    if [[ "$arg" == "-C" ]] && ((i + 1 < n)); then
      if [[ "${a[i + 1]}" == /* || "${a[i + 1]}" =~ ^[A-Za-z]:[\/] ]]; then
        base="${a[i + 1]}"
      else
        base="$base/${a[i + 1]}"
      fi
      ((i++))
    fi
  done
  printf '%s' "$base"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sequencer_in_progress() {
  local dir repo="$1" f
  dir=$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  [[ -n "$dir" ]] || return 1
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ -e "$dir/$f" ]] && return 0
  done
  return 1
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local gi sub sub_idx nseg k word next stdin_form=0 exempt=0

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  # gh pr create --title validation (independent of git parsing). `gh` is
  # commonly wrapped in command-scoped environment settings
  # (`GH_PROMPT_DISABLED=1 gh …`, `env GH_TOKEN=… gh …`) — skip leading
  # assignments and `env`/`command` wrappers before deciding this is not gh.
  local -a gw=("$@")
  local gn=$# gs=0 gt
  while ((gs < gn)); do
    gt="${gw[gs]}"
    if [[ "$gt" == *=* && "$gt" != -* ]]; then
      ((gs++))
      continue
    fi
    case "${gt##*/}" in
    env | command)
      ((gs++))
      while ((gs < gn)) && [[ "${gw[gs]}" == -* || ("${gw[gs]}" == *=* && "${gw[gs]}" != -*) ]]; do ((gs++)); done
      continue
      ;;
    *) break ;;
    esac
  done
  if [[ -n "$TITLE_ERE" && "${gw[gs]:-}" == "gh" && "${gw[gs + 1]:-}" == "pr" && "${gw[gs + 2]:-}" == "create" ]]; then
    local t="" ti
    for ((ti = gs + 3; ti < gn; ti++)); do
      case "${gw[ti]}" in
      --title)
        ((ti + 1 < gn)) && t="${gw[ti + 1]}"
        ;;
      --title=*)
        t="${gw[ti]#--title=}"
        ;;
      -t)
        ((ti + 1 < gn)) && t="${gw[ti + 1]}"
        ;;
      *) ;;
      esac
    done
    if [[ -n "$t" ]] && ! [[ "$t" =~ $TITLE_ERE ]]; then
      block_title "$t"
    fi
    return 0
  fi

  [[ -n "$SUBJECT_ERE" ]] || return 0

  hook::git_resolve_index "$@" || return 0
  gi=$HOOK_GIT_RESOLVED_GI
  w=("${HOOK_GIT_RESOLVED_WORDS[@]}")
  nseg=${#w[@]}

  hook::git_resolve_subcommand "$gi" "${w[@]}" || return 0
  sub=$HOOK_GIT_SUB
  sub_idx=$HOOK_GIT_SUB_IDX

  # Alias-expanded commits must be content-gated too (`git -c alias.c=commit c
  # -F - <<EOF` and persisted `git qc` aliases create commits) — mirror the
  # sibling mechanic guard's expansion: re-check every inline spelling, then
  # the gitconfig-resolved alias, one level (HOOK_NO_ALIAS bounds recursion).
  # rc 2 (--config-env-shaped alias) is the MECHANIC guard's fail-closed
  # concern — it blocks the call outright, so this content gate just skips.
  local exp reparse a alias_rc inline_alias_handled=0
  local -a expw=()
  hook::git_alias_expansion "$sub"
  alias_rc=$?
  ((alias_rc == 2)) && return 0
  if ((${HOOK_NO_ALIAS:-0} == 0)); then
    if ((alias_rc == 0)); then
      # shellcheck disable=SC2154  # HOOK_GIT_ALIAS_EXPS is set by hook::git_alias_expansion
      for exp in ${HOOK_GIT_ALIAS_EXPS[@]+"${HOOK_GIT_ALIAS_EXPS[@]}"}; do
        [[ -n "$exp" ]] || continue
        inline_alias_handled=1
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
      done
    fi
    if ((inline_alias_handled == 0)) && [[ "$sub" != "commit" ]]; then
      local pexp
      pexp=$(git -C "$(effective_dir "${w[@]}")" config --get "alias.$sub" 2>/dev/null)
      if [[ -n "$pexp" ]]; then
        if [[ "$pexp" == '!'* ]]; then
          local preparse pa
          preparse="${pexp#!}"
          for pa in "${w[@]:sub_idx+1}"; do preparse+=" $(printf '%q' "$pa")"; done
          hook::bash_parse_segments "$preparse" check_segment
        else
          local -a pexpw=()
          hook::env_s_split "$pexp"
          pexpw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          HOOK_NO_ALIAS=1
          check_segment "${w[@]:0:gi+1}" ${pexpw[@]+"${pexpw[@]}"} "${w[@]:sub_idx+1}"
          HOOK_NO_ALIAS=0
        fi
      fi
    fi
  fi

  [[ "$sub" == "commit" ]] || return 0

  for ((k = sub_idx + 1; k < nseg; k++)); do
    word="${w[k]}"
    next=""
    ((k + 1 < nseg)) && next="${w[k + 1]}"
    case "$word" in
    --) break ;;
    -F | --file)
      if [[ "$next" == "-" ]]; then stdin_form=1; else exempt=1; fi
      ((k++))
      ;;
    -F- | --file=-) stdin_form=1 ;;
    --file=* | -F*) exempt=1 ;;
    --amend | --fixup | --squash | -C | -c | --reuse-message | --reedit-message) exempt=1 ;;
    --fixup=* | --squash=* | --reuse-message=* | --reedit-message=*) exempt=1 ;;
    -C* | -c*) exempt=1 ;;
    *) ;;
    esac
  done

  ((stdin_form)) || return 0
  ((exempt)) && return 0
  sequencer_in_progress "$(effective_dir "${w[@]}")" && return 0

  local subj=""
  if [[ "$TOOL_NAME" == "PowerShell" ]]; then
    subj=$(first_herestring_subject "$COMMAND")
  else
    subj=$(first_heredoc_subject "$COMMAND")
  fi
  # No extractable message body (non-heredoc stdin producer): content unknown,
  # skip — form is the mechanic gate's concern, and guessing here would block
  # compliant subjects it cannot see.
  [[ -n "$subj" ]] || return 0

  [[ "$subj" =~ $SUBJECT_ERE ]] || block_subject "$subj"
  return 0
}

if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  # Reduce the PowerShell command to a Bash-tokenizer-faithful form, or defer:
  # rc 1 (provably git-free unparsable) has nothing to gate — and if it could
  # still carry a `gh pr create`, the quote-intact reduced text was already
  # scanned by the classifier's own sink; rc 2 (git-shaped unparsable) is
  # block-noncanonical-commit's fail-closed concern, not a content decision.
  ps::classify_git_command "$TOOL_NAME" "$COMMAND"
  ps_rc=$?
  ((ps_rc == 0)) || {
    emit_tel "ok" ""
    exit 0
  }
  hook::bash_parse_segments "$PS_SAFE_COMMAND" check_segment
else
  hook::bash_parse_segments "$COMMAND" check_segment
fi

emit_tel "ok" ""
exit 0
