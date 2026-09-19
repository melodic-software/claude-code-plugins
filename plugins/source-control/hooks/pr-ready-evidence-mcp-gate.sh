#!/usr/bin/env bash
# PreToolUse hook: the MCP-surface sibling of pr-ready-evidence-gate.sh.
#
# WHY IT EXISTS. Cloud and remote sessions have no `gh` CLI and flip a pull
# request to ready for review through the GitHub MCP server, as
# `mcp__github__update_pull_request` with `draft: false`. That surface the Bash
# sibling never sees. Same verdict, same reader, same advisory posture, on the
# payload shape the MCP tool delivers: where the Bash sibling has to tokenize a
# command line to find the flip, here it is a plain JSON field, so the
# extraction caveats do not exist on this surface.
#
# ADVISORY, ALWAYS. The verdict travels on `additionalContext` and the exit
# status is 0 on every path. It is a nudge, not a gate: the `ci-status`
# validator reports the same gap on every flip however the flip was made. The
# hook records nothing of its own, since the validator's comment marker is the
# count of record for the promotion window.
#
# SCOPE GUARDS. Only `mcp__github__update_pull_request` carrying `draft: false`
# is in scope: an update with no `draft` field, or one setting `draft: true`,
# does not flip anything to ready. A call whose `owner`/`repo` do not match this
# checkout's origin remote is out of scope and silent, as in the sibling
# pr-linkage-mcp-gate: this repository's evidence map is not another
# repository's. When the match cannot be ESTABLISHED, because there is no origin
# remote or the payload names no owner and repo, the target is undeterminable
# and the call is silent for the same reason.
#
# Kill switch: pr_ready_evidence_gate_enabled userConfig option, shared with the
# Bash sibling. One flip turns the nudge off on both surfaces, which is what an
# operator who wants it off means.

set -uo pipefail

# Pinned for the whole process, as in the sibling gates, so no verdict below
# depends on the ambient locale.
export LC_ALL=C

# Kill switch FIRST, above every source: a disabled gate must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics.
[[ "${CLAUDE_PLUGIN_OPTION_PR_READY_EVIDENCE_GATE_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`: a command
# substitution forks a subshell even for a builtin body, and on Windows Git Bash
# that fork is a process.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

hook::buffer_stdin_to INPUT || exit 0
[[ -n "$INPUT" ]] || exit 0

hook::require_jq "PreToolUse" "source-control-pr-ready-evidence-mcp-gate" "$INPUT"

# Every payload field in ONE jq process, the shape the sibling MCP gate uses.
# `draft` rides along as its JSON text, so `false` is distinguishable from an
# absent field (which renders as the empty string) without a second probe.
hook::jq_fields "$INPUT" '.tool_name' '.cwd' \
  '.tool_input.owner' '.tool_input.repo' \
  '(if (.tool_input | type) == "object" and (.tool_input | has("draft")) then (.tool_input.draft | tojson) else "" end)' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
T_OWNER="${HOOK_JQ_FIELDS[2]}"
T_REPO="${HOOK_JQ_FIELDS[3]}"
DRAFT="${HOOK_JQ_FIELDS[4]}"

# hook::jq_fields CR-strips but does not chomp trailing newlines, which the
# `$(jq ...)` form it replaced did: without this, an `"owner": "acme\n"` would
# miss the exact-match guard below.
chomp() {
  local __v="${!1}"
  while [[ "$__v" == *$'\n' ]]; do __v="${__v%$'\n'}"; done
  printf -v "$1" '%s' "$__v"
}
for v in TOOL HOOK_CWD T_OWNER T_REPO DRAFT; do chomp "$v"; done

[[ "$TOOL" == "mcp__github__update_pull_request" ]] || exit 0
# Only a flip OUT of draft is a ready flip. An absent field changes no draft
# state, and `true` converts the pull request back to a draft.
[[ "$DRAFT" == "false" ]] || exit 0

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || exit 0

# Origin-match scope guard, the sibling MCP gate's approach: the origin URL's
# separators are normalized so https, ssh (`git@host:owner/repo`) and proxied
# forms all end in `/owner/repo`, and the comparison is case-insensitive because
# GitHub routing is. The redirect sits on the enclosing GROUP, not inside the
# substitution: bash elides the substitution's own extra fork only when the
# command carries no redirection of its own.
{ ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin) || ORIGIN=""; } 2>/dev/null
[[ -n "$ORIGIN" && -n "$T_OWNER" && -n "$T_REPO" ]] || exit 0
norm="${ORIGIN%/}"
norm="${norm%.git}"
norm="${norm//:/\/}"
[[ "${norm,,}" == *"/${T_OWNER,,}/${T_REPO,,}" ]] || exit 0

# notice <key> <message>: one visible skip notice per (session, agent) for an
# environment this gate cannot read, then silence. Every caller exits 0 after.
notice() {
  hook::notice_once "$1" "$INPUT" && hook::emit_skip_notice "PreToolUse" "$2"
  return 0
}

{ HEAD_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD) || HEAD_SHA=""; } 2>/dev/null
if [[ -z "$HEAD_SHA" ]]; then
  notice "source-control-pr-ready-evidence-head" \
    "source-control pr-ready-evidence-mcp-gate: $REPO_ROOT has no HEAD commit, so the pre-PR skill evidence for this ready flip cannot be read. The flip was allowed."
  exit 0
fi

# The base branch the diff is classified against. `refs/remotes/origin/HEAD` is
# the recorded default branch; `origin/main` is the fallback for a checkout that
# never had one set.
{ BASE_REF=$(git -C "$REPO_ROOT" symbolic-ref -q refs/remotes/origin/HEAD) || BASE_REF=""; } 2>/dev/null
if [[ -z "$BASE_REF" ]]; then
  if git -C "$REPO_ROOT" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    BASE_REF="origin/main"
  fi
fi
if [[ -z "$BASE_REF" ]]; then
  notice "source-control-pr-ready-evidence-base" \
    "source-control pr-ready-evidence-mcp-gate: neither refs/remotes/origin/HEAD nor origin/main resolves in $REPO_ROOT, so the changed-file classes for this ready flip cannot be detected. The flip was allowed. Run \`git fetch origin\` and \`git remote set-head origin -a\` to give the gate a base."
  exit 0
fi

# The ledger location, from this plugin's own option. The scope words mirror
# claude-ops' skill_usage_scope, which is the option that WRITES the ledger;
# anything else is read as a path, with a leading `~/` expanded.
STORE="${CLAUDE_PLUGIN_OPTION_SKILL_EVIDENCE_STORE:-repo}"
case "$STORE" in
repo | "") LEDGER="$REPO_ROOT/.claude/observability/skill-usage.jsonl" ;;
user) LEDGER="${HOME:-}/.claude/observability/skill-usage.jsonl" ;;
*)
  # A path. The strip pattern escapes the tilde so nothing expands here; a
  # value that carried a leading `~/` is joined to $HOME instead.
  LEDGER="${STORE#\~/}"
  [[ "$LEDGER" != "$STORE" ]] && LEDGER="${HOME:-}/$LEDGER"
  ;;
esac

if [[ ! -f "$LEDGER" ]]; then
  notice "source-control-pr-ready-evidence-ledger" \
    "source-control pr-ready-evidence-mcp-gate: no skill-usage ledger at $LEDGER, so the pre-PR skill evidence for this ready flip cannot be read. The flip was allowed. That ledger is written by the claude-ops plugin: enable it, and set its skill_usage_scope option and this plugin's skill_evidence_store option to the same scope word. Set pr_ready_evidence_gate_enabled to false to turn this gate off."
  exit 0
fi

# The one reader of the evidence rule, shared with the ready step, the ci-status
# validator and the babysit merge gate, so no reader drifts from another.
EVIDENCE_SH="${CLAUDE_PLUGIN_ROOT:-}"
if [[ -n "$EVIDENCE_SH" ]]; then
  EVIDENCE_SH="$EVIDENCE_SH/scripts/skill-evidence.sh"
else
  EVIDENCE_SH="$HOOK_DIR/../scripts/skill-evidence.sh"
fi

REPORT=""
RC=0
{ REPORT=$(CLAUDE_PROJECT_DIR="$REPO_ROOT" "$EVIDENCE_SH" check \
  --head "$HEAD_SHA" --ledger "$LEDGER" --base "$BASE_REF") || RC=$?; } 2>/dev/null
if ((RC != 0)); then
  notice "source-control-pr-ready-evidence-script" \
    "source-control pr-ready-evidence-mcp-gate: scripts/skill-evidence.sh exited $RC, so the pre-PR skill evidence for this ready flip could not be read. The flip was allowed."
  exit 0
fi

# `verdict=inert` (no map, so the mechanism is off in this repository) and
# `verdict=clean` (every mandatory skill has a fresh row) both say nothing.
case "$REPORT" in
*"verdict=gap"*) ;;
*) exit 0 ;;
esac

CTX="source-control pr-ready-evidence-mcp-gate: this call flips a pull request to ready for review, but the skill-usage ledger carries no fresh evidence at HEAD $HEAD_SHA that every mandatory pre-PR skill ran."
# Split in the shell rather than `while read < <(...)` or a here-string: both
# hand the text to a reader through a file descriptor bash has to set up, and
# this loop needs neither a fork nor a temporary file.
rest="$REPORT"
while [[ -n "$rest" ]]; do
  line="${rest%%$'\n'*}"
  if [[ "$line" == "$rest" ]]; then rest=""; else rest="${rest#*$'\n'}"; fi
  case "$line" in
  missing=*) CTX+=$'\n'"  missing: ${line#missing=}" ;;
  stale=*) CTX+=$'\n'"  stale: ${line#stale=}" ;;
  *) ;;
  esac
done
CTX+=$'\n'"Run \`/source-control:pull-request ready\` instead of flipping directly. It runs the missing skills against the committed head, commits anything they change, and re-renders the evidence block in the pull request body before the flip."
CTX+=$'\n'"This notice is advisory and the call was allowed."

hook::emit_channels "PreToolUse" "$CTX" ""
exit 0
