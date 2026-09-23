# shellcheck shell=bash
# Shared ready-for-review EVIDENCE VERDICT. Sourced (not executed) by every
# hook that judges a ready flip against the mandatory pre-PR skill evidence:
#   - pr-ready-evidence-gate.sh      (Bash surface: `gh pr ready`, the GraphQL
#                                     mutation, the cloud proxy's route)
#   - pr-ready-evidence-mcp-gate.sh  (MCP surface: update_pull_request with
#                                     draft: false)
# Each consumer decides on its own whether the call IS a flip on this checkout;
# once it is, everything from "which commit is under review" to the nudge text
# is the same on both surfaces and lives here once, so a change to the ledger
# location, the base-ref rule or the wording reaches every surface at once.
#
# CONTRACT. The caller has sourced hook-utils.sh, buffered the payload into
# INPUT (hook::notice_once keys its once-per-session marker on it), and set
# HOOK_DIR (the fallback location of scripts/skill-evidence.sh when
# CLAUDE_PLUGIN_ROOT is unset). Sourcing happens AFTER the caller's scope
# guards, so an out-of-scope call never pays to read this file.
#
# ADVISORY, ALWAYS. pr_ready_evidence::judge returns 0 on every path and emits
# at most one thing: a once-per-session skip notice for an environment it
# cannot read, or the `additionalContext` nudge on `verdict=gap`. It never
# blocks, and it records nothing of its own: the ci-status validator's comment
# marker is the count of record for the promotion window.

# Guard against double-sourcing.
[[ -n "${_PR_READY_EVIDENCE_VERDICT_LOADED:-}" ]] && return 0
readonly _PR_READY_EVIDENCE_VERDICT_LOADED=1

# pr_ready_evidence::notice <key> <message>: one visible skip notice per
# (session, agent) for an environment this gate cannot read, then silence.
pr_ready_evidence::notice() {
  # shellcheck disable=SC2154  # INPUT is the sourcing gate's buffered payload (CONTRACT above)
  hook::notice_once "$1" "$INPUT" && hook::emit_skip_notice "PreToolUse" "$2"
  return 0
}

# pr_ready_evidence::judge <gate-name> <repo-root> <target>: read the ledger
# through scripts/skill-evidence.sh check against HEAD and, on a gap, name the
# skills that are owed. <gate-name> prefixes every message so a reader knows
# which surface spoke.
#
# <target> is WHICH pull request the call names, because the ledger and HEAD
# describe this checkout's branch and nothing else: a flip of some other pull
# request from the same checkout must not be judged by this branch's rows.
#   ""              the current branch's pull request (gh's own default)
#   "#<n>"          a pull request number (a `gh pr ready <n>` operand, a URL's
#                   trailing number, the cloud route's path, the MCP payload)
#   "branch:<name>" a branch name operand
#   "opaque"        a form that cannot be matched here (a GraphQL node id)
# A number is matched against `branch.<current>.pr-number`, the key the create
# step records; a branch against the current branch. A target that is provably
# another pull request is silent, and one that cannot be matched is noticed
# once and left unjudged. Neither is ever a nudge about the wrong branch.
pr_ready_evidence::judge() {
  local gate="$1" repo_root="$2" target="${3:-}"
  local head_sha branch number recorded base_ref store ledger evidence_sh report rc ctx rest line

  # HEAD and the branch name in ONE git spawn: two output lines, the SHA first.
  # The redirect sits on the enclosing GROUP, not inside the substitution: bash
  # elides the substitution's own extra fork only when the command carries no
  # redirection of its own.
  { head_sha=$(git -C "$repo_root" rev-parse HEAD --abbrev-ref HEAD) || head_sha=""; } 2>/dev/null
  branch="${head_sha#*$'\n'}"
  head_sha="${head_sha%%$'\n'*}"
  [[ "$branch" == "$head_sha" || "$branch" == "HEAD" ]] && branch=""
  if [[ -z "$head_sha" ]]; then
    pr_ready_evidence::notice "source-control-pr-ready-evidence-head" \
      "source-control $gate: $repo_root has no HEAD commit, so the pre-PR skill evidence for this ready flip cannot be read. The flip was allowed."
    return 0
  fi

  case "$target" in
  "") ;;
  opaque)
    pr_ready_evidence::notice "source-control-pr-ready-evidence-target" \
      "source-control $gate: this call flips a pull request to ready for review, but it names the pull request in a form this gate cannot match to this checkout (a GraphQL node id), so the pre-PR skill evidence was not judged. The flip was allowed. Flip with \`gh pr ready <number>\` or \`/source-control:pull-request ready\` to have the evidence judged."
    return 0
    ;;
  "#"*)
    number="${target#\#}"
    recorded=""
    if [[ -n "$branch" ]]; then
      { recorded=$(git -C "$repo_root" config --get "branch.$branch.pr-number") || recorded=""; } 2>/dev/null
    fi
    if [[ -z "$recorded" ]]; then
      pr_ready_evidence::notice "source-control-pr-ready-evidence-target" \
        "source-control $gate: this call flips pull request #$number to ready for review, but this checkout${branch:+"'s branch $branch"} records no pull request number, so the gate cannot tell whether #$number is this branch's pull request; the pre-PR skill evidence was not judged. The flip was allowed. \`/source-control:pull-request create\` records the number at creation; \`git config branch.${branch:-<branch>}.pr-number $number\` records it by hand."
      return 0
    fi
    # Another pull request from this checkout: this branch's rows say nothing
    # about it.
    [[ "$recorded" == "$number" ]] || return 0
    ;;
  branch:*)
    [[ -n "$branch" && "${target#branch:}" == "$branch" ]] || return 0
    ;;
  *) ;;
  esac

  # The base branch the diff is classified against. `refs/remotes/origin/HEAD`
  # is the recorded default branch; `origin/main` is the fallback for a
  # checkout that never had one set.
  { base_ref=$(git -C "$repo_root" symbolic-ref -q refs/remotes/origin/HEAD) || base_ref=""; } 2>/dev/null
  if [[ -z "$base_ref" ]]; then
    if git -C "$repo_root" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
      base_ref="origin/main"
    fi
  fi
  if [[ -z "$base_ref" ]]; then
    pr_ready_evidence::notice "source-control-pr-ready-evidence-base" \
      "source-control $gate: neither refs/remotes/origin/HEAD nor origin/main resolves in $repo_root, so the changed-file classes for this ready flip cannot be detected. The flip was allowed. Run \`git fetch origin\` and \`git remote set-head origin -a\` to give the gate a base."
    return 0
  fi

  # The ledger location, from this plugin's own option. The scope words mirror
  # claude-ops' skill_usage_scope, which is the option that WRITES the ledger;
  # anything else is read as a path, with a leading `~/` expanded.
  store="${CLAUDE_PLUGIN_OPTION_SKILL_EVIDENCE_STORE:-repo}"
  case "$store" in
  repo | "") ledger="$repo_root/.claude/observability/skill-usage.jsonl" ;;
  user) ledger="${HOME:-}/.claude/observability/skill-usage.jsonl" ;;
  *)
    # A path. The strip pattern escapes the tilde so nothing expands here; a
    # value that carried a leading `~/` is joined to $HOME instead.
    ledger="${store#\~/}"
    [[ "$ledger" != "$store" ]] && ledger="${HOME:-}/$ledger"
    ;;
  esac

  if [[ ! -f "$ledger" ]]; then
    pr_ready_evidence::notice "source-control-pr-ready-evidence-ledger" \
      "source-control $gate: no skill-usage ledger at $ledger, so the pre-PR skill evidence for this ready flip cannot be read. The flip was allowed. That ledger is written by the claude-ops plugin: enable it, and set its skill_usage_scope option and this plugin's skill_evidence_store option to the same scope word. Set pr_ready_evidence_gate_enabled to false to turn this gate off."
    return 0
  fi

  # The one reader of the evidence rule, shared with the ready step, the
  # ci-status validator and the babysit merge gate, so no reader drifts from
  # another.
  evidence_sh="${CLAUDE_PLUGIN_ROOT:-}"
  if [[ -n "$evidence_sh" ]]; then
    evidence_sh="$evidence_sh/scripts/skill-evidence.sh"
  else
    # shellcheck disable=SC2154  # HOOK_DIR is set by the sourcing gate (CONTRACT above)
    evidence_sh="$HOOK_DIR/../scripts/skill-evidence.sh"
  fi

  report=""
  rc=0
  { report=$(CLAUDE_PROJECT_DIR="$repo_root" "$evidence_sh" check \
    --head "$head_sha" --ledger "$ledger" --base "$base_ref") || rc=$?; } 2>/dev/null
  if ((rc != 0)); then
    pr_ready_evidence::notice "source-control-pr-ready-evidence-script" \
      "source-control $gate: scripts/skill-evidence.sh exited $rc, so the pre-PR skill evidence for this ready flip could not be read. The flip was allowed."
    return 0
  fi

  # `verdict=inert` (no map, so the mechanism is off in this repository) and
  # `verdict=clean` (every mandatory skill has a fresh row) both say nothing.
  case "$report" in
  *"verdict=gap"*) ;;
  *) return 0 ;;
  esac

  ctx="source-control $gate: this call flips a pull request to ready for review, but the skill-usage ledger carries no fresh evidence at HEAD $head_sha that every mandatory pre-PR skill ran."
  # Split in the shell rather than `while read < <(...)` or a here-string: both
  # hand the text to a reader through a file descriptor bash has to set up, and
  # this loop needs neither a fork nor a temporary file.
  rest="$report"
  while [[ -n "$rest" ]]; do
    line="${rest%%$'\n'*}"
    if [[ "$line" == "$rest" ]]; then rest=""; else rest="${rest#*$'\n'}"; fi
    case "$line" in
    missing=*) ctx+=$'\n'"  missing: ${line#missing=}" ;;
    stale=*) ctx+=$'\n'"  stale: ${line#stale=}" ;;
    *) ;;
    esac
  done
  ctx+=$'\n'"Run \`/source-control:pull-request ready\` instead of flipping directly. It runs the missing skills against the committed head, commits anything they change, and re-renders the evidence block in the pull request body before the flip."
  ctx+=$'\n'"This notice is advisory and the call was allowed."

  hook::emit_channels "PreToolUse" "$ctx" ""
  return 0
}
