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
  '(if (.tool_input | type) == "object" and (.tool_input | has("draft")) then (.tool_input.draft | tojson) else "" end)' \
  '(.tool_input.pullNumber // "" | tostring)' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
T_OWNER="${HOOK_JQ_FIELDS[2]}"
T_REPO="${HOOK_JQ_FIELDS[3]}"
DRAFT="${HOOK_JQ_FIELDS[4]}"
T_NUMBER="${HOOK_JQ_FIELDS[5]}"

# hook::jq_fields CR-strips but does not chomp trailing newlines, which the
# `$(jq ...)` form it replaced did: without this, an `"owner": "acme\n"` would
# miss the exact-match guard below.
chomp() {
  local __v="${!1}"
  while [[ "$__v" == *$'\n' ]]; do __v="${__v%$'\n'}"; done
  printf -v "$1" '%s' "$__v"
}
for v in TOOL HOOK_CWD T_OWNER T_REPO DRAFT T_NUMBER; do chomp "$v"; done

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

# The verdict from here on is the same on every flip surface: which commit is
# under review, where the ledger is, what scripts/skill-evidence.sh says about
# it, and the nudge. It lives once in pr-ready-evidence-verdict.sh, sourced only
# now so an out-of-scope call never pays to read it.
# shellcheck source=pr-ready-evidence-verdict.sh
# The payload names the pull request by number, which the verdict matches
# against the number the create step recorded for this checkout's branch; a
# payload without one is a form that cannot be matched.
if [[ "$T_NUMBER" =~ ^[0-9]+$ ]]; then
  TARGET="#$T_NUMBER"
else
  TARGET="opaque"
fi
source "$HOOK_DIR/pr-ready-evidence-verdict.sh"
pr_ready_evidence::judge "pr-ready-evidence-mcp-gate" "$REPO_ROOT" "$TARGET"
exit 0
